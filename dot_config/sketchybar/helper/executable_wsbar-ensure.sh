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

# Cheap check first: no need to start a process just to find out one is running
# (the pid files live in /tmp, which is cleared at boot, so a recycled pid is not a concern)
alive() {
  [ -s "$1" ] || return 1
  local pid
  read -r pid < "$1"
  kill -0 "$pid" 2>/dev/null
}

ARG_WS="--keep"
ARG_SYS=""
if [ "$1" = "restart" ]; then
  ARG_WS=""
  ARG_SYS="--replace"
fi

if [ "$1" = "restart" ] || ! alive "/tmp/wsbar.$UID_.pid"; then
  CONFIG_DIR="$DIR" nohup /usr/bin/python3 "$DIR/helper/wsbar.py" $ARG_WS >> "/tmp/wsbar.$UID_.out" 2>&1 &
  disown 2>/dev/null
fi

if [ -x "$DIR/helper/sysstat" ] && { [ "$1" = "restart" ] || ! alive "/tmp/sysstat.$UID_.pid"; }; then
  CONFIG_DIR="$DIR" nohup "$DIR/helper/sysstat" --daemon $ARG_SYS >> "/tmp/sysstat.$UID_.out" 2>&1 &
  disown 2>/dev/null
fi
exit 0
