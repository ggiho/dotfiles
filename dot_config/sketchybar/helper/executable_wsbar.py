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
WORKSPACES = ["1", "2", "3", "4"]
BASE_SLOTS = 8                  # slots the rc creates; more are added on demand
POLL_SECONDS = 3.0
HEAL_SECONDS = 20.0
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
            log("DBG SEND %s" % "+".join(kinds))
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
            wins = s.windows.get(ws, []) if ws == s.focused_ws else []
            for i, (wid, bundle, app) in enumerate(wins, 1):
                if i > self.slots[ws]:
                    self.send(args)        # keep order: earlier --set first, then the new item
                    args = []
                    self.add_slot(ws, i)
                item = "wsapp.%s.%d" % (ws, i)
                hl = "on" if wid == s.focused_id else "off"
                static = "on|%s|%s" % (bundle, wid)
                if self.img.get(item) != static:
                    args += ["--set", item, "drawing=on", "icon.background.image=app." + bundle,
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
            if ws in shown:
                # real screen order: left to right, then top to bottom
                def key(r):
                    f = frames.get(r[0])
                    return (f[0], f[1], int(r[0])) if f else (99999, 99999, int(r[0]))
                tiled.sort(key=key)
            else:
                # not on screen (parked windows have no meaningful position): keep the old order
                tiled.sort(key=lambda r: (prev_order.index(r[0]) if r[0] in prev_order else 10 ** 6, int(r[0])))
            self.windows[ws] = [(r[0], r[3], r[4]) for r in tiled]
        # The focus comes from AeroSpace events. A lookup right after a switch still reports the
        # OLD focused window until macOS finishes activating the new one, so it must not overwrite
        # the event-driven focus; it is only used to bootstrap when nothing is known yet.
        if focused and self.focused_id is None:
            self.focused_id, self.focused_ws = focused[0], focused[1]


def take_snapshot():
    """All the slow lookups, in parallel. Returns a dict, or None if AeroSpace did not answer."""
    with ThreadPoolExecutor(max_workers=4) as ex:
        f_all = ex.submit(run, [AEROSPACE, "list-windows", "--all", "--format",
                                "%{window-id}|%{workspace}|%{window-layout}|%{app-bundle-id}|%{app-name}"])
        f_foc = ex.submit(run, [AEROSPACE, "list-windows", "--focused", "--format",
                                "%{window-id}|%{workspace}"])
        f_fr = ex.submit(run, [FRAMES])
        f_ws = ex.submit(run, [AEROSPACE, "list-workspaces", "--all", "--format",
                               "%{workspace}|%{monitor-id}|%{workspace-is-visible}"])
        all_out, foc_out, fr_out, ws_out = f_all.result(), f_foc.result(), f_fr.result(), f_ws.result()
    rows = [l.split("|") for l in all_out.split("\n") if l.count("|") == 4]
    if not rows and not ws_out:
        return None
    focused = None
    p = foc_out.strip().split("|")
    if len(p) == 2:
        focused = (p[0], p[1])         # (window id, workspace)
    frames = {}
    for l in fr_out.split("\n"):
        q = l.split()
        if len(q) == 5:
            frames[q[0]] = (int(q[1]), int(q[2]), q[3], q[4])
    wsinfo = {}
    for l in ws_out.split("\n"):
        q = l.split("|")
        if len(q) == 3:
            wsinfo[q[0]] = (int(q[1]), q[2] == "true")
    return {"rows": rows, "focused": focused, "frames": frames, "wsinfo": wsinfo}


class Daemon:
    def __init__(self):
        self.q = queue.Queue()
        self.state = State()
        self.bar = Bar()
        self.refresh_pending = False
        self.poll_busy = False
        self.last_struct = None
        self.last_frames = None
        self.suspects = {}       # window id -> time first flagged
        self.cooldown = {}       # window id -> time last floated
        self.last_heal = time.time()
        self.last_switch = 0.0
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
                                      "focused-monitor-changed", "window-detected"],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
                self.children.append(p)
                log("subscribed to AeroSpace events")
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
                p.wait()
                self.children.remove(p)
            except Exception as e:
                log("appwatch error: %s" % e)
            time.sleep(2.0)

    def request_refresh(self, delay=0.05):
        if self.refresh_pending:
            return
        self.refresh_pending = True
        threading.Timer(delay, lambda: self.q.put(("refresh", 0))).start()

    def ticker(self):
        while True:
            time.sleep(POLL_SECONDS)
            self.q.put(("tick", 0))

    # ---- workers ---------------------------------------------------------------------------
    def refresh_worker(self):
        snap = take_snapshot()
        if snap:
            self.q.put(("snapshot", snap))

    def poll_worker(self):
        try:
            snap = take_snapshot()
            if not snap:
                return
            now = time.time()
            struct = hash((tuple(map(tuple, snap["rows"])), snap["focused"]))
            tiled_ids = {r[0] for r in snap["rows"] if r[2] != "floating" and "minimized" not in r[2]}
            fsig = hash(tuple(sorted((k, v) for k, v in snap["frames"].items() if k in tiled_ids)))
            fresh = {k: t for k, t in self.suspects.items() if now - t < 30}
            self.suspects = fresh
            if struct != self.last_struct:
                self.last_struct, self.last_frames = struct, fsig
                self.suspects.clear()
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
                    app = next((r[4] for r in snap["rows"] if r[0] == i), "?")
                    run([AEROSPACE, "layout", "floating", "--window-id", i])
                    with open(SHAKE_LOG, "a") as f:
                        f.write("%s floated window %s (%s): its frame kept flipping while tiled\n"
                                % (time.strftime("%F %T"), i, app))
                    refresh = True
                if refresh:
                    self.q.put(("snapshot", take_snapshot() or snap))
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
        if wid is None and ws and ws != prev:
            # 'workspace changed' can arrive before 'focus changed': AeroSpace goes back to the
            # window last focused there, so assume it now; the real event corrects it if wrong
            wid = s.last_focus.get(ws)
        s.set_focus(wid, ws)
        if mon is not None and ws:
            s.visible_by_monitor[mon] = ws
        if s.focused_ws != prev:
            self.last_switch = time.time()
            self.request_refresh(0.1)
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
        if DEBUG and kind in ("event", "settle", "snapshot"):
            log("DBG %s %s" % (kind, json.dumps(payload) if kind == "event" else ""))
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
            elif e == "window-detected":
                wid = str(payload.get("windowId"))
                s.app_of[wid] = payload.get("appName", "")
                self.request_refresh(0.15)
        elif kind == "mac":
            self.on_mac_activate(*payload)
        elif kind == "guard":
            self.check_guard(*payload)
        elif kind == "snapshot":
            s.apply_snapshot(payload)
        elif kind == "refresh":
            self.refresh_pending = False
            threading.Thread(target=self.refresh_worker, daemon=True).start()
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
        threading.Thread(target=self.ticker, daemon=True).start()
        self.loop()


def take_lock(replace):
    """One instance only, race-free: whoever holds the flock on PIDFILE is the instance. With
    `replace` an older instance is asked to quit and this one takes over; without it this one
    just gives up. (Checking a pid file and then writing it let two starts that happen at the
    same moment both win.) Returns the open file, which must stay open for the process lifetime."""
    f = open(PIDFILE, "a+")
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


def main():
    lock = None
    if not DRYRUN:
        lock = take_lock(replace="--keep" not in sys.argv)
    log("wsbar started (dryrun=%s)" % DRYRUN)
    Daemon().run()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
