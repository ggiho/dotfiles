#!/usr/bin/python3
"""wsbar: event-driven workspace bar for SketchyBar + AeroSpace.

One long-running process replaces the old chain (AeroSpace callback -> bash -> sketchybar --trigger
-> several scripts). It subscribes to AeroSpace events over a socket, keeps the state in memory and
updates the number, the app icons, the highlight and the front-app name with ONE sketchybar call
per change, so everything changes at the same moment.

  - numbers:   focused (red) / shown on another monitor (blue) / plain
  - icons:     full-color app icons of the focused workspace's tiled windows, in real screen order
  - highlight: the focused window's icon
  - label:     the front app's name (set here, so it can no longer run ahead of the icons)
  - guard:     a tiled window whose frame keeps flipping (app minimum size vs tile) is floated

Set WSBAR_DRYRUN=1 to log the sketchybar calls instead of sending them.
"""
import fcntl
import itertools
import json
import os
import queue
import re
import signal
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

HOME = os.path.expanduser("~")
CONFIG_DIR = os.environ.get("CONFIG_DIR", HOME + "/.config/sketchybar")
AEROSPACE = "/opt/homebrew/bin/aerospace"
SKETCHYBAR = "/opt/homebrew/bin/sketchybar"
FRAMES = CONFIG_DIR + "/helper/winframes"
APPWATCH = CONFIG_DIR + "/helper/appwatch"
WORKSPACES = ["7", "8", "9", "0"]
BASE_SLOTS = 8                  # slots the rc creates; more are added on demand
POLL_SECONDS = 3.0
INPUT_QUIET_SECONDS = 5.0         # after one of the user's key bindings, moved windows are not a shake
SWITCH_QUIET_SECONDS = 4.0        # after a workspace switch the periodic check only re-baselines
STRUCT_POLL_SECONDS = 60.0      # how often AeroSpace is asked for the full window list when nothing seems to change
HEAL_SECONDS = 20.0
RECHECK_SECONDS = 1.0           # a second look when AeroSpace still lists a window the system no longer has
COALESCE_SECONDS = 0.008        # wait this long for sibling events before drawing
SETTLE_SECONDS = 0.35           # hold window after a switch (see on_focus_event)
GUARD_SECONDS = 0.6             # how long after a click on an app we wait before checking it got focus
GUARD_GAP = 2.0                 # at most one corrective focus per this many seconds
UID = os.getuid()
DRYRUN = bool(os.environ.get("WSBAR_DRYRUN"))
DEBUG = os.path.exists("/tmp/wsbar-debug-on")      # touch this file to log every event and decision
PIDFILE = "/tmp/wsbar.%d.pid" % UID      # also the lock file: the running instance holds a flock on it
LOGFILE = "/tmp/wsbar.%d.log" % UID
SHAKE_LOG = "/tmp/sketchybar-ws-apps.shake.log"


def log(msg):
    try:
        if os.path.exists(LOGFILE) and os.path.getsize(LOGFILE) > 200000:
            open(LOGFILE, "w").close()
        with open(LOGFILE, "a") as f:
            f.write("%.3f %s\n" % (time.time(), msg))
    except Exception:
        pass


def run(cmd, timeout=6):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception as e:
        log("run failed %s: %s" % (cmd[:3], e))
        return ""


def load_colors():
    """Read colors.sh: 'export NAME=0x...' and 'export NAME=$OTHER' (resolved, a few levels deep)."""
    raw = {}
    with open(CONFIG_DIR + "/colors.sh") as f:
        for line in f:
            m = re.match(r"export (\w+)=(\S+)", line.strip())
            if m:
                raw[m.group(1)] = m.group(2)
    colors = {}
    for name in raw:
        value = raw[name]
        for _ in range(5):
            if value.startswith("$"):
                value = raw.get(value[1:], value)
        colors[name] = value
    return colors


C = load_colors()


class Bar:
    """Everything that talks to sketchybar, with a memory of what is already drawn."""

    def __init__(self):
        self.img = {}        # item -> "on|bundle|id|"  (set together with the image/click action)
        self.cheap = {}      # item -> drawing/highlight/number state (cheap, re-assertable)
        self.slots = {ws: BASE_SLOTS for ws in WORKSPACES}
        self.label = None
        self.read_slot_counts()

    def read_slot_counts(self):
        out = run([SKETCHYBAR, "--query", "bar"])
        try:
            items = json.loads(out).get("items", [])
        except Exception:
            return
        for ws in WORKSPACES:
            n = len([i for i in items if re.match(r"^wsapp\.%s\.\d+$" % ws, i)])
            if n:
                self.slots[ws] = n

    def send(self, args):
        if not args:
            return
        if DRYRUN:
            log("DRYRUN sketchybar " + " ".join(args))
            return
        if DEBUG:
            kinds = [k for k, m in (("NUM", "icon.highlight="), ("ICON", "icon.background.image="),
                                    ("HL", "background.drawing="), ("NAME", "front_app")) if any(m in a for a in args)]
            # which items this update touches, and the properties that matter for what is visible
            shown = ("icon.background.image=", "background.drawing=", "icon.highlight=", "drawing=")
            parts, item = [], None
            for a in args:
                if a == "--set":
                    item = None
                elif item is None:
                    item = a
                elif a.startswith(shown):
                    parts.append("%s:%s" % (item, a.replace("icon.background.image=app.", "img=")[:60]))
            log("DBG SEND %s | %s" % ("+".join(kinds), " ".join(parts)[:400]))
        try:
            subprocess.run([SKETCHYBAR] + args, capture_output=True, timeout=6)
        except Exception as e:
            log("sketchybar failed: %s" % e)

    def add_slot(self, ws, n):
        a = ["--add", "item", "wsapp.%s.%d" % (ws, n), "left",
             "--set", "wsapp.%s.%d" % (ws, n),
             "drawing=off", "updates=off", "icon= ", "icon.width=26",
             "icon.padding_left=1", "icon.padding_right=1",
             "icon.background.drawing=on", "icon.background.image.scale=0.85",
             "label.drawing=off", "padding_left=1", "padding_right=1",
             "background.drawing=off", "background.height=28", "background.corner_radius=7",
             "background.color=0x33ffffff", "background.border_color=" + C.get("WHITE", "0xffffffff")]
        self.send(a)
        if n > 1:
            self.send(["--move", "wsapp.%s.%d" % (ws, n), "after", "wsapp.%s.%d" % (ws, n - 1)])
        self.slots[ws] = max(self.slots[ws], n)
        # a new slot knows nothing yet
        self.img.pop("wsapp.%s.%d" % (ws, n), None)
        self.cheap.pop("wsapp.%s.%d" % (ws, n), None)

    def heal(self):
        """Forget the cheap state so the next render re-asserts it (images are not touched)."""
        self.cheap.clear()
        self.label = None

    def render(self, s):
        args = []
        # workspace numbers
        for ws in WORKSPACES:
            if ws == s.focused_ws:
                sel, col, bor = "on", C["ICON_COLOR"], C["GREY"]
            elif s.shown_elsewhere(ws):
                sel, col, bor = "off", C["BLUE"], C["BLUE"]
            else:
                sel, col, bor = "off", C["ICON_COLOR"], C["BACKGROUND_2"]
            sig = (sel, col, bor)
            if self.cheap.get("space." + ws) != sig:
                args += ["--set", "space." + ws, "icon.highlight=" + sel, "icon.color=" + col,
                         "background.border_color=" + bor]
                self.cheap["space." + ws] = sig

        # app icons: only the focused workspace is expanded
        for ws in WORKSPACES:
            wins = s.icons.get(ws, []) if ws == s.focused_ws else []
            hl_id = s.highlighted(ws) if ws == s.focused_ws else None
            for i, (wid, bundle, app, floating) in enumerate(wins, 1):
                if i > self.slots[ws]:
                    self.send(args)        # keep order: earlier --set first, then the new item
                    args = []
                    self.add_slot(ws, i)
                item = "wsapp.%s.%d" % (ws, i)
                hl = "on" if wid == hl_id else "off"
                static = "on|%s|%s|%s" % (bundle, wid, "f" if floating else "t")
                if self.img.get(item) != static:
                    args += ["--set", item, "drawing=on", "icon.background.image=app." + bundle,
                             # the pill follows the icon: 26 wide and 28 high fit the 0.85 icons exactly
                             "icon.background.image.scale=" + ("0.7" if floating else "0.85"),
                             "icon.width=" + ("22" if floating else "26"),
                             "background.height=" + ("24" if floating else "28"),
                             "background.drawing=" + hl,
                             "click_script=%s focus --window-id %s" % (AEROSPACE, wid)]
                    self.img[item] = static
                    self.cheap[item] = ("on", hl)
                elif self.cheap.get(item) != ("on", hl):
                    args += ["--set", item, "drawing=on", "background.drawing=" + hl]
                    self.cheap[item] = ("on", hl)
            for i in range(len(wins) + 1, self.slots[ws] + 1):
                item = "wsapp.%s.%d" % (ws, i)
                if self.cheap.get(item) != ("off",):
                    args += ["--set", item, "drawing=off"]
                    self.cheap[item] = ("off",)
                    self.img.pop(item, None)

        # front app name, from the same state so it changes together with the icons
        name = s.app_of.get(s.focused_id)
        if DEBUG:
            log("DBG render ws=%s focused_id=%s name=%s shown_label=%s" % (s.focused_ws, s.focused_id, name, self.label))
        if name and name != self.label:
            args += ["--set", "front_app", "label=" + name, "label.drawing=on"]
            self.label = name

        self.send(args)


class State:
    def __init__(self):
        self.focused_ws = None
        self.focused_id = None
        self.windows = {}         # ws -> [(id, bundle, app)] tiled windows in screen order
        self.icons = {}           # ws -> [(id, bundle, app, floating)]: what the bar shows (tiled, then floating apps)
        self.app_of = {}          # window id -> app name (every window, floating too)
        self.ws_monitor = {}      # ws -> monitor id
        self.last_focus = {}      # ws -> last focused window id (predicts the focus on a switch)
        self.last_focus_by_app = {}    # app name -> last focused window id
        self.visible_by_monitor = {}   # monitor id -> visible ws

    def shown_elsewhere(self, ws):
        return ws != self.focused_ws and ws in self.visible_by_monitor.values()

    def set_focus(self, wid, ws):
        if wid is not None:
            self.focused_id = wid
            if ws:
                self.last_focus[ws] = wid
            if self.app_of.get(wid):
                self.last_focus_by_app[self.app_of[wid]] = wid
        if ws:
            self.focused_ws = ws
            mon = self.ws_monitor.get(ws)
            if mon is not None:
                self.visible_by_monitor[mon] = ws

    def highlighted(self, ws):
        """Id of the icon that stands for the focused window: its own, or else the icon of its app
        (a floating window of an app that is shown by another window's icon)."""
        icons = self.icons.get(ws, [])
        if any(i[0] == self.focused_id for i in icons):
            return self.focused_id
        app = self.app_of.get(self.focused_id)
        return next((i[0] for i in icons if i[2] == app), None) if app else None

    def apply_snapshot(self, snap):
        rows, focused, frames, wsinfo = snap["rows"], snap["focused"], snap["frames"], snap["wsinfo"]
        if wsinfo:
            self.ws_monitor = {w: m for w, (m, v) in wsinfo.items()}
            self.visible_by_monitor = {m: w for w, (m, v) in wsinfo.items() if v}
        self.app_of = {r[0]: r[4] for r in rows}
        shown = set(self.visible_by_monitor.values())
        for ws in WORKSPACES:
            tiled = [r for r in rows if r[1] == ws and r[2] != "floating" and "minimized" not in r[2]]
            prev_order = [w[0] for w in self.windows.get(ws, [])]
            if ws in shown and any("accordion" in r[2] for r in tiled):
                # The frames of an accordion follow the focus (the focused window moves in front of the others),
                # so sorting by them reorders the icons at every focus move and the highlight jumps around.
                # AeroSpace lists the windows of a workspace in layout order, which does not change: keep it.
                pass
            elif ws in shown:
                # real screen order: left to right, then top to bottom
                def key(r):
                    f = frames.get(r[0])
                    return (f[0], f[1], int(r[0])) if f else (99999, 99999, int(r[0]))
                tiled.sort(key=key)
            else:
                # not on screen (parked windows have no meaningful position): keep the old order
                tiled.sort(key=lambda r: (prev_order.index(r[0]) if r[0] in prev_order else 10 ** 6, int(r[0])))
            self.windows[ws] = [(r[0], r[3], r[4]) for r in tiled]
            # Floating windows have no place in the layout, but the bar should still show where the focus
            # is when it is on one: one icon per app (several Finder windows are one icon), after the tiled
            # ones, and none for an app that already has a tiled icon.
            icons = [(r[0], r[3], r[4], False) for r in tiled]
            seen = {r[4] for r in tiled}
            for r in sorted((r for r in rows if r[1] == ws and r[2] == "floating"), key=lambda r: int(r[0])):
                if r[4] not in seen:
                    seen.add(r[4])
                    icons.append((r[0], r[3], r[4], True))
            self.icons[ws] = icons
        # The focus comes from AeroSpace events. A lookup right after a switch still reports the
        # OLD focused window until macOS finishes activating the new one, so it must not overwrite
        # the event-driven focus; it is only used to bootstrap when nothing is known yet.
        if focused and self.focused_id is None:
            self.focused_id, self.focused_ws = focused[0], focused[1]


WINDOW_FORMAT = "%{window-id}|%{workspace}|%{window-layout}|%{app-bundle-id}|%{app-name}"


def parse_rows(out):
    return [l.split("|") for l in out.split("\n") if l.count("|") == 4]


def parse_frames(out):
    frames = {}
    for l in out.split("\n"):
        q = l.split()
        if len(q) == 5:
            frames[q[0]] = (int(q[1]), int(q[2]), q[3], q[4])
    return frames


def poll_frames():
    """On-screen windows and their frames, straight from the system (CGWindowList through winframes).
    AeroSpace is deliberately not asked: `list-windows --all` makes it re-read every app's windows
    through the accessibility API, which cost it ~2% of a core when done every 3 seconds."""
    return parse_frames(run([FRAMES]))


_TICKETS = itertools.count(1)


def take_snapshot():
    """All the slow lookups, in parallel. Returns a dict, or None if AeroSpace did not answer.
    The dict carries a ticket, numbered when the look started (see Daemon.handle, "snapshot")."""
    ticket = next(_TICKETS)
    with ThreadPoolExecutor(max_workers=4) as ex:
        f_all = ex.submit(run, [AEROSPACE, "list-windows", "--all", "--format", WINDOW_FORMAT])
        f_foc = ex.submit(run, [AEROSPACE, "list-windows", "--focused", "--format",
                                "%{window-id}|%{workspace}"])
        f_fr = ex.submit(run, [FRAMES])
        f_ws = ex.submit(run, [AEROSPACE, "list-workspaces", "--all", "--format",
                               "%{workspace}|%{monitor-id}|%{workspace-is-visible}"])
        all_out, foc_out, fr_out, ws_out = f_all.result(), f_foc.result(), f_fr.result(), f_ws.result()
    rows = parse_rows(all_out)
    if not rows and not ws_out:
        return None
    focused = None
    p = foc_out.strip().split("|")
    if len(p) == 2:
        focused = (p[0], p[1])         # (window id, workspace)
    frames = parse_frames(fr_out)
    wsinfo = {}
    for l in ws_out.split("\n"):
        q = l.split("|")
        if len(q) == 3:
            wsinfo[q[0]] = (int(q[1]), q[2] == "true")
    return {"rows": rows, "focused": focused, "frames": frames, "wsinfo": wsinfo, "ticket": ticket}


class Daemon:
    def __init__(self):
        self.q = queue.Queue()
        self.state = State()
        self.bar = Bar()
        self.refresh_pending = False
        self.refresh_full = False      # a pending refresh has to ask AeroSpace for everything
        self.refresh_check = False     # a pending refresh first checks whether the set of windows changed
        self.last_rows = None          # window list of the last snapshot, reused by light refreshes
        self.poll_busy = False
        self.last_ids = None         # on-screen window ids at the last poll
        self.last_full = 0.0         # when AeroSpace was last asked for the full window list by the poll
        self.last_frames = None
        self.suspects = {}       # window id -> time first flagged
        self.cooldown = {}       # window id -> time last floated
        self.last_heal = time.time()
        self.recheck_pending = False
        self.verify_after = False     # a window or app went: the next full look is checked against the system's list
        self.applied_ticket = 0       # the newest look at the system that has been shown
        self.last_switch = 0.0
        self.last_input = 0.0        # when the user last triggered an AeroSpace key binding
        self.pending = None
        self.children = []         # helper processes to stop together with this one
        self.mac_front = None      # app macOS last activated
        self.aero_focus = (0.0, None)   # (time, app) of the last AeroSpace focus-changed event
        self.aero_recent = []      # (time, app) of recent AeroSpace focus-changed events
        self.guard = None          # (app, time, bounced, seen): an app the user just activated
        self.last_fix = 0.0

    # ---- producers -------------------------------------------------------------------------
    def subscribe_loop(self):
        while True:
            try:
                p = subprocess.Popen([AEROSPACE, "subscribe", "focus-changed", "focused-workspace-changed",
                                      "focused-monitor-changed", "window-detected", "binding-triggered"],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
                self.children.append(p)
                log("subscribed to AeroSpace events")
                self.refresh_full = True       # first look after (re)connecting: everything
                self.q.put(("refresh", 0))
                for line in p.stdout:
                    try:
                        self.q.put(("event", json.loads(line)))
                    except ValueError:
                        pass
                p.wait()
                self.children.remove(p)
            except Exception as e:
                log("subscribe error: %s" % e)
            log("AeroSpace event stream ended; reconnecting")
            time.sleep(1.0)

    def appwatch_loop(self):
        """macOS app activations (Dock click, Cmd+Tab, Raycast) from the small appwatch helper."""
        if not os.path.exists(APPWATCH):
            log("appwatch helper missing; activation guard is off")
            return
        while True:
            try:
                p = subprocess.Popen([APPWATCH], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     text=True, bufsize=1)
                self.children.append(p)
                for line in p.stdout:
                    kind, _, name = line.rstrip("\n").partition("\t")
                    if kind == "activate" and name:
                        self.q.put(("mac", (name, time.time())))
                    elif kind == "terminate" and name:
                        self.q.put(("terminated", name))
                p.wait()
                self.children.remove(p)
            except Exception as e:
                log("appwatch error: %s" % e)
            time.sleep(2.0)

    def winwatch_loop(self):
        """`winframes --watch` prints a line whenever a window comes or goes. AeroSpace has no event for a
        closed window, so this is what makes an icon disappear when its window closes."""
        while True:
            started = time.time()
            try:
                p = subprocess.Popen([FRAMES, "--watch"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     text=True, bufsize=1)
                self.children.append(p)
                for line in p.stdout:
                    if line.strip() == "change":
                        self.q.put(("winchange", 0))
                p.wait()
                self.children.remove(p)
            except Exception as e:
                log("winframes watch error: %s" % e)
            # an older winframes without --watch prints the frames and exits at once: do not respawn it in a loop
            time.sleep(5.0 if time.time() - started < 3 else 1.0)

    def request_refresh(self, delay=0.05, full=True, check_ids=False):
        """full: ask AeroSpace for everything. Not full: only re-read the window frames (the system's
        window list) and reuse the window list we already have; that is enough after a workspace
        switch, and it keeps AeroSpace free to switch (its full window listing makes it re-read every
        app's windows, right while it is busy focusing the new one).
        check_ids: first compare the set of windows with the last look; if a window came or went it is
        a full refresh after all."""
        if full:
            self.refresh_full = True
        if check_ids:
            self.refresh_check = True
        if self.refresh_pending:
            return
        self.refresh_pending = True
        threading.Timer(delay, lambda: self.q.put(("refresh", 0))).start()

    def recheck_later(self):
        """AeroSpace can still list a window for a moment after it closed, so the look that follows a change
        may show the old state. One more look a second later settles it."""
        if self.recheck_pending:
            return
        self.recheck_pending = True
        threading.Timer(RECHECK_SECONDS, lambda: self.q.put(("recheck", 0))).start()

    def ticker(self):
        while True:
            time.sleep(POLL_SECONDS)
            self.q.put(("tick", 0))

    # ---- workers ---------------------------------------------------------------------------
    def refresh_worker(self, full, check_ids=False):
        if not full and self.last_rows:
            ticket = next(_TICKETS)
            frames = poll_frames()
            if frames and not (check_ids and self.last_ids is not None and frozenset(frames) != self.last_ids):
                self.q.put(("snapshot", {"rows": self.last_rows, "focused": None, "frames": frames, "wsinfo": None,
                                         "light": True, "ticket": ticket}))
                return
        snap = take_snapshot()
        if snap:
            self.q.put(("snapshot", snap))

    def poll_worker(self):
        """Every few seconds: look at the system's window list (cheap, no AeroSpace). Only when the set
        of windows changed (or every STRUCT_POLL_SECONDS as a safety net) ask AeroSpace for everything."""
        try:
            frames = poll_frames()
            now = time.time()
            if not frames:
                # winframes is missing or failing (a new machine before its Swift helpers were built):
                # the system's window list is not available, so the slow safety net is all there is
                if now - self.last_full > STRUCT_POLL_SECONDS:
                    self.last_full = now
                    snap = take_snapshot()
                    if snap:
                        self.q.put(("snapshot", snap))
                return
            ids = frozenset(frames)
            if now - self.last_switch < SWITCH_QUIET_SECONDS and self.last_ids is not None and ids == self.last_ids:
                # a workspace switch moves every window on and off the screen: that is not shaking, so
                # take the new positions as the baseline. (Parked windows stay in the system's list, so
                # the set of windows only differs when one really came or went: that is not skipped.)
                tiled = {w[0] for ws in WORKSPACES for w in self.state.windows.get(ws, [])}
                self.last_frames = hash(tuple(sorted((k, v) for k, v in frames.items() if k in tiled)))
                return
            if ids != self.last_ids or now - self.last_full > STRUCT_POLL_SECONDS:
                self.last_ids, self.last_full = ids, now
                snap = take_snapshot()
                if snap:
                    self.suspects.clear()
                    tiled = {r[0] for r in snap["rows"] if r[2] != "floating" and "minimized" not in r[2]}
                    self.last_frames = hash(tuple(sorted((k, v) for k, v in snap["frames"].items() if k in tiled)))
                    self.q.put(("snapshot", snap))
                return
            # same windows: only shaking is left to look for (the tiled ones, as known from the last snapshot)
            tiled_ids = {w[0] for ws in WORKSPACES for w in self.state.windows.get(ws, [])}
            fsig = hash(tuple(sorted((k, v) for k, v in frames.items() if k in tiled_ids)))
            fresh = {k: t for k, t in self.suspects.items() if now - t < 30}
            self.suspects = fresh
            if now - self.last_input < INPUT_QUIET_SECONDS:
                # The user is moving or resizing windows with the keys (swapping two windows back and forth
                # looks exactly like a shake). That is not a fight with an app: only redraw the bar.
                self.suspects.clear()
                if fsig != self.last_frames:
                    self.last_frames = fsig
                    snap = take_snapshot()
                    if snap:
                        self.q.put(("snapshot", snap))
                return
            if fsig != self.last_frames or fresh:
                refresh = fsig != self.last_frames
                self.last_frames = fsig
                shaking = self.sample_shaking(tiled_ids)
                confirmed = [i for i in shaking if i in fresh]
                for i in shaking:
                    if i not in fresh:
                        self.suspects[i] = now
                for i in confirmed:
                    self.suspects.pop(i, None)
                    if now - self.cooldown.get(i, 0) < 300:
                        continue
                    self.cooldown[i] = now
                    app = self.state.app_of.get(i, "?")
                    run([AEROSPACE, "layout", "floating", "--window-id", i])
                    with open(SHAKE_LOG, "a") as f:
                        f.write("%s floated window %s (%s): its frame kept flipping while tiled\n"
                                % (time.strftime("%F %T"), i, app))
                    refresh = True
                if refresh:
                    snap = take_snapshot()
                    if snap:
                        self.q.put(("snapshot", snap))
        finally:
            self.poll_busy = False

    def sample_shaking(self, tiled_ids):
        """Six quick frame samples; ids that flipped between at most two frames at least twice."""
        samples = []
        for i in range(6):
            if i:
                time.sleep(0.1)
            fr = {}
            for l in run([FRAMES]).split("\n"):
                q = l.split()
                if len(q) == 5 and q[0] in tiled_ids:
                    fr[q[0]] = tuple(q[1:])
            samples.append(fr)
        out = []
        for wid in tiled_ids:
            seq = [s[wid] for s in samples if wid in s]
            changes = sum(1 for a, b in zip(seq, seq[1:]) if a != b)
            if changes >= 2 and len(set(seq)) <= 2:
                out.append(wid)
        return out

    # ---- consumer (the only place that mutates state or draws) --------------------------------
    def apply_focus(self, wid, ws, mon=None):
        s = self.state
        prev = s.focused_ws
        prev_id = s.focused_id
        if wid is None and ws and ws != prev:
            # 'workspace changed' can arrive before 'focus changed': AeroSpace goes back to the
            # window last focused there, so assume it now; the real event corrects it if wrong
            wid = s.last_focus.get(ws)
        s.set_focus(wid, ws)
        if mon is not None and ws:
            s.visible_by_monitor[mon] = ws
        if s.focused_ws != prev:
            self.last_switch = time.time()
            self.request_refresh(0.1, full=False)
            # the windows are still settling at 0.1 s: read their frames once more when they are done
            threading.Timer(0.7, lambda: self.request_refresh(0.0, full=False)).start()
        elif wid and prev_id and wid != prev_id:
            # Another window of this workspace got the focus. AeroSpace has no event for a closed window,
            # but closing the focused one ends here: look at the system's window list (cheap) to see.
            self.request_refresh(0.15, full=False, check_ids=True)
        if wid and wid not in s.app_of:
            self.request_refresh()

    def on_focus_event(self, wid, ws, mon=None):
        """The first switch is drawn at once. Right after a switch AeroSpace/macOS can briefly report
        the OLD workspace again before settling, so an event for a different workspace inside the
        hold window is parked and only applied if it is still the latest when the window ends."""
        s = self.state
        now = time.time()
        within = now - self.last_switch < SETTLE_SECONDS
        if ws and s.focused_ws and ws != s.focused_ws and within:
            self.pending = (wid, ws, mon)
            threading.Timer(SETTLE_SECONDS - (now - self.last_switch) + 0.02,
                            lambda: self.q.put(("settle", 0))).start()
            return
        self.pending = None          # back on the shown workspace (or no switch in progress)
        self.apply_focus(wid, ws, mon)

    # ---- activation guard --------------------------------------------------------------------
    # Clicking an app that lives on a hidden workspace in the Dock makes macOS activate it, and
    # AeroSpace follows. But with an auto-hidden Dock, AeroSpace's mouse-up handler takes the Dock
    # click for a click on the bare desktop of that monitor and focuses the workspace that is
    # visible there, so the click first lands on the wrong workspace (and that focus' activation can
    # arrive late and pull it back again). See AeroSpace GlobalObserver.swift / discussion #2223.
    # Turning the Dock's auto-hide off removes the cause; this guard repairs the result instead:
    # if the app does not end up focused shortly after the activation, focus its window (once).
    def on_mac_activate(self, name, t):
        self.mac_front = name
        aero_t, aero_app = self.aero_focus
        if DEBUG:
            log("DBG mac activate %s (last aero focus: %s, %.0f ms earlier)" % (name, aero_app, (t - aero_t) * 1000))
        # If AeroSpace itself focused this app a moment ago (not only as its very last move: it can
        # try one window, correct itself, and the first activation arrives late), macOS is just
        # catching up and this is not the user asking for the app.
        if any(a == name and t - ta < 0.6 for ta, a in self.aero_recent):
            if DEBUG:
                log("DBG mac activate %s ignored: AeroSpace focused it recently" % name)
            return
        # the focus-changed that undoes the click can reach us a hair before the activation itself
        bounced = aero_app is not None and aero_app != name and t - aero_t < 0.05
        self.guard = (name, t, bounced, False)
        threading.Timer(GUARD_SECONDS, lambda: self.q.put(("guard", (name, t)))).start()

    def guard_target(self, name):
        s = self.state
        wid = s.last_focus_by_app.get(name)
        if wid in s.app_of:
            return wid
        tiled = [w[0] for ws in WORKSPACES for w in s.windows.get(ws, []) if w[2] == name]
        if tiled:
            return tiled[0]
        return next((w for w, a in s.app_of.items() if a == name), None)

    def check_guard(self, name, t):
        g = self.guard
        if not g or g[0] != name or g[1] != t:
            if DEBUG:
                log("DBG guard-check %s: skipped (newer activation took over)" % name)
            return                  # a newer activation took over
        self.guard = None
        # the latest raw AeroSpace event, not the bar's state (which holds back flicker for a moment)
        focused_app = self.aero_focus[1]
        if DEBUG:
            log("DBG guard-check %s: aero_focus=%s mac_front=%s bounced=%s" % (name, focused_app, self.mac_front, g[2]))
        if focused_app == name and self.mac_front == name:
            return                  # it worked
        if not g[2]:
            return                  # AeroSpace never moved the focus elsewhere: not this problem
        self.fix_focus(name, focused_app)

    def fix_focus(self, name, focused_app):
        wid = self.guard_target(name)
        now = time.time()
        if wid is None or now - self.last_fix < GUARD_GAP:
            return
        self.last_fix = now
        log("GUARD %s was activated but AeroSpace focused %s; focusing window %s" % (name, focused_app, wid))
        threading.Thread(target=run, args=([AEROSPACE, "focus", "--window-id", wid],), daemon=True).start()

    def handle(self, kind, payload):
        s = self.state
        if DEBUG and kind in ("event", "settle", "snapshot", "terminated", "refresh"):
            extra = json.dumps(payload) if kind == "event" else ""
            if kind == "snapshot":
                extra = "rows=%d light=%s apps=%s" % (len(payload["rows"]), bool(payload.get("light")), sorted({r[4] for r in payload["rows"]}))[:160]
            elif kind == "terminated":
                extra = payload
            log("DBG %s %s" % (kind, extra))
        if kind == "settle":
            if self.pending:
                wid, ws, mon = self.pending
                self.pending = None
                if ws != s.focused_ws:
                    self.apply_focus(wid, ws, mon)
        elif kind == "event":
            e = payload.get("_event")
            if e == "focus-changed":
                wid = str(payload.get("windowId")) if payload.get("windowId") is not None else None
                app = s.app_of.get(wid)
                now = time.time()
                self.aero_focus = (now, app)
                self.aero_recent = [(ta, a) for ta, a in self.aero_recent if now - ta < 2.0]
                if app:
                    self.aero_recent.append((now, app))
                g = self.guard
                if g and now - g[1] < GUARD_SECONDS + 0.4:
                    if app == g[0]:
                        self.guard = (g[0], g[1], g[2], True)
                    elif app is not None:
                        if g[3]:
                            # it reached the app and then moved away again (e.g. it followed a late
                            # activation of another app): put the focus back now, not after the timer
                            self.guard = None
                            if DEBUG:
                                log("DBG guard %s: focus left the app again; fixing at once" % g[0])
                            self.fix_focus(g[0], app)
                        else:
                            self.guard = (g[0], g[1], True, g[3])
                self.on_focus_event(wid, payload.get("workspace"))
            elif e == "focused-workspace-changed":
                self.on_focus_event(None, payload.get("workspace"))
            elif e == "focused-monitor-changed":
                self.on_focus_event(None, payload.get("workspace"), payload.get("monitorId"))
            elif e == "binding-triggered":
                self.last_input = time.time()
            elif e == "window-detected":
                wid = str(payload.get("windowId"))
                s.app_of[wid] = payload.get("appName", "")
                self.request_refresh(0.15)
        elif kind == "mac":
            self.on_mac_activate(*payload)
        elif kind == "winchange":
            self.request_refresh(0.1)          # a window came or went
            self.verify_after = True
        elif kind == "terminated":
            self.request_refresh(0.2)          # an app quit: its icons must go (AeroSpace has no event for it)
            self.verify_after = True
        elif kind == "recheck":
            self.recheck_pending = False
            self.request_refresh(0.05)
        elif kind == "guard":
            self.check_guard(*payload)
        elif kind == "snapshot":
            # Looks run in parallel threads and can arrive in any order. One that started before the one already
            # shown carries older facts (e.g. a window AeroSpace still listed a moment after it closed): showing
            # it would bring back what was just fixed, and nothing would look again for a minute.
            if payload.get("ticket", 0) < self.applied_ticket:
                return
            self.applied_ticket = payload.get("ticket", 0)
            s.apply_snapshot(payload)
            if self.verify_after and not payload.get("light"):
                self.verify_after = False
                # AeroSpace lists a window that the system no longer has: it has not caught up yet (or the app is
                # hidden). Look once more a second later; when the two agree nothing more is asked of AeroSpace.
                if any(r[0] not in payload["frames"] for r in payload["rows"] if "minimized" not in r[2]):
                    self.recheck_later()
            self.last_rows = payload["rows"]
            if payload.get("frames") and not payload.get("light"):
                # the baseline for "did the set of windows change": only from a look at AeroSpace's window
                # list (a light refresh reuses the old list, so a window closed meanwhile would be hidden)
                self.last_ids = frozenset(payload["frames"])
        elif kind == "refresh":
            self.refresh_pending = False
            full, self.refresh_full = self.refresh_full, False
            check, self.refresh_check = self.refresh_check, False
            threading.Thread(target=self.refresh_worker, args=(full, check), daemon=True).start()
        elif kind == "tick":
            if not self.poll_busy:
                self.poll_busy = True
                threading.Thread(target=self.poll_worker, daemon=True).start()
            if time.time() - self.last_heal > HEAL_SECONDS:
                self.bar.heal()
                self.last_heal = time.time()

    def loop(self):
        while True:
            kind, payload = self.q.get()
            self.handle(kind, payload)
            if kind == "event":
                time.sleep(COALESCE_SECONDS)     # the sibling events of one switch arrive together
            # whatever else already arrived is merged first, so a burst of events draws once
            try:
                while True:
                    kind, payload = self.q.get_nowait()
                    self.handle(kind, payload)
            except queue.Empty:
                pass
            self.bar.render(self.state)

    def stop_children(self, *_):
        for p in list(self.children):
            try:
                p.terminate()
            except Exception:
                pass
        os._exit(0)

    def run(self):
        signal.signal(signal.SIGTERM, self.stop_children)
        threading.Thread(target=self.subscribe_loop, daemon=True).start()
        threading.Thread(target=self.appwatch_loop, daemon=True).start()
        threading.Thread(target=self.winwatch_loop, daemon=True).start()
        threading.Thread(target=self.ticker, daemon=True).start()
        self.loop()


def take_lock(replace):
    """One instance only, race-free: whoever holds the flock on PIDFILE is the instance. With
    `replace` an older instance is asked to quit and this one takes over; without it this one
    just gives up. (Checking a pid file and then writing it let two starts that happen at the
    same moment both win.) Returns the open file, which must stay open for the process lifetime."""
    f = os.fdopen(os.open(PIDFILE, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600), "r+")
    deadline = time.time() + 3.0
    asked = None
    while True:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError:
            if not replace or time.time() > deadline:
                sys.exit(0)
            f.seek(0)
            try:
                old = int(f.read().strip())
            except ValueError:
                old = None            # the holder has locked but not written its pid yet
            if old and old != asked and "wsbar.py" in run(["/bin/ps", "-p", str(old), "-o", "command="]):
                os.kill(old, signal.SIGTERM)
                asked = old
            time.sleep(0.05)
    f.seek(0)
    f.truncate()
    f.write(str(os.getpid()))
    f.flush()
    return f


def reap_orphans():
    """After a hard kill (kill -9) an earlier instance leaves its helper processes without a parent.
    Stop the ones that are exactly ours: the event subscription and the app and window watchers."""
    for l in run(["/bin/ps", "-axo", "pid=,ppid=,command="]).splitlines():
        parts = l.split(None, 2)
        if len(parts) < 3 or parts[1] != "1":
            continue
        cmd = parts[2]
        if (cmd.startswith(AEROSPACE + " subscribe focus-changed focused-workspace-changed") or cmd.split()[0] == APPWATCH
                or cmd.startswith(FRAMES + " --watch")):
            try:
                os.kill(int(parts[0]), signal.SIGTERM)
            except OSError:
                pass


def main():
    lock = None
    if not DRYRUN:
        lock = take_lock(replace="--keep" not in sys.argv)
        reap_orphans()
    log("wsbar started (dryrun=%s)" % DRYRUN)
    Daemon().run()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
