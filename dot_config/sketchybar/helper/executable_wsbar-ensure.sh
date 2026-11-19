#!/bin/bash
# Make sure the bar's two resident helpers are running:
#   helper/wsbar.py          workspace numbers, app icons, highlight (follows AeroSpace events)
#   helper/sysstat --daemon  CPU and memory labels of the bar (refreshes every few seconds)
#
#   wsbar-ensure.sh            start whichever is not running (used by the watchdog item)
#   wsbar-ensure.sh restart    start fresh ones (used by sketchybarrc); a new process takes over from
#                              an older one by itself
# Both hold a lock on their pid file, so several starts at the same moment still end up with exactly
# one instance (a plain start gives up if one is running, "restart" takes over).

DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
UID_="$(id -u)"

STATE="$HOME/.local/state/wsbar"
mkdir -p "$STATE"

# Cheap check first: no need to start a process just to find out one is running.
# If the pid file is missing or stale, look for the process itself before starting another one: two daemons would
# answer every event twice. (The pid files used to be in /tmp, where macOS deletes old files.)
alive() {
  local pid
  if [ -s "$1" ]; then
    read -r pid < "$1"
    kill -0 "$pid" 2>/dev/null && return 0
  fi
  pgrep -f "$2" >/dev/null 2>&1
}

ARG_WS="--keep"
ARG_SYS=""
if [ "$1" = "restart" ]; then
  ARG_WS=""
  ARG_SYS="--replace"
  # stop the running ones by name too: a daemon that lost its pid file can not be found through it
  pkill -TERM -f "helper/wsbar\.py" 2>/dev/null
  pkill -TERM -f "helper/sysstat --daemon" 2>/dev/null
  sleep 0.5
fi

if [ "$1" = "restart" ] || ! alive "$STATE/wsbar.pid" "helper/wsbar\.py"; then
  CONFIG_DIR="$DIR" nohup /usr/bin/python3 "$DIR/helper/wsbar.py" $ARG_WS >> "/tmp/wsbar.$UID_.out" 2>&1 &
  disown 2>/dev/null
fi

if [ -x "$DIR/helper/sysstat" ] && { [ "$1" = "restart" ] || ! alive "$STATE/sysstat.pid" "helper/sysstat --daemon"; }; then
  CONFIG_DIR="$DIR" nohup "$DIR/helper/sysstat" --daemon $ARG_SYS >> "/tmp/sysstat.$UID_.out" 2>&1 &
  disown 2>/dev/null
fi
exit 0
