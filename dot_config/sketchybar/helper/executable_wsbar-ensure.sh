#!/bin/bash
# Make sure helper/wsbar.py is running.
#   wsbar-ensure.sh            start it only if it is not running (used by the watchdog item)
#   wsbar-ensure.sh restart    always start a fresh one (used by sketchybarrc); the new process
#                              replaces an older one by itself

PIDFILE="/tmp/wsbar.$(id -u).pid"
DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"

if [ "$1" != "restart" ] && [ -f "$PIDFILE" ]; then
  pid="$(cat "$PIDFILE")"
  if kill -0 "$pid" 2>/dev/null && /bin/ps -p "$pid" -o command= | grep -q "wsbar.py"; then
    exit 0
  fi
fi

CONFIG_DIR="$DIR" nohup /usr/bin/python3 "$DIR/helper/wsbar.py" >> "/tmp/wsbar.$(id -u).out" 2>&1 &
disown 2>/dev/null
exit 0
