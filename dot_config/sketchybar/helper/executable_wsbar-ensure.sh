#!/bin/bash
# Make sure helper/wsbar.py is running.
#   wsbar-ensure.sh            start it only if it is not running (used by the watchdog item)
#   wsbar-ensure.sh restart    always start a fresh one (used by sketchybarrc); the new process
#                              replaces an older one by itself
# wsbar.py holds a lock on its pid file, so several starts at the same moment still end up with
# exactly one instance (a plain start gives up if one is running, "restart" takes over).

PIDFILE="/tmp/wsbar.$(id -u).pid"
DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"

# Cheap check first: no need to start python just to find out an instance is running
# (the pid file lives in /tmp, which is cleared at boot, so a recycled pid is not a concern)
if [ "$1" != "restart" ] && [ -s "$PIDFILE" ]; then
  read -r pid < "$PIDFILE"
  kill -0 "$pid" 2>/dev/null && exit 0
fi

ARG="--keep"
[ "$1" = "restart" ] && ARG=""
CONFIG_DIR="$DIR" nohup /usr/bin/python3 "$DIR/helper/wsbar.py" $ARG >> "/tmp/wsbar.$(id -u).out" 2>&1 &
disown 2>/dev/null
exit 0
