#!/bin/bash
# Events of the cpu and mem items of the bar. The labels themselves are refreshed by the resident
# helper/sysstat --daemon; this script only closes popups (see barpopup.sh, which opens them).

SEQ="/tmp/barpopup.$(id -u).seq"
dbg() { [ -e /tmp/wsbar-debug-on ] && echo "$(date +%T.%N | cut -c1-12) $*" >> /tmp/barpopup.log; }

# The mouse left the item and its popup: close the popup. (Not reliable on its own, hence the other
# ways below and the auto close in barpopup.sh.)
if [ "$SENDER" = "mouse.exited.global" ]; then
  dbg "$NAME exit-event -> close"
  # also invalidates an open that is still being prepared
  echo $(($(cat "$SEQ" 2>/dev/null || echo 0) + 1)) > "$SEQ"
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

# Another app (or monitor) got the focus. A popup is drawn on the focused display, so it would jump
# along to it; close it. The focus move that barpopup.sh does itself right before opening is ignored:
# its event can reach this script a second late on a busy machine, hence the 1.5 s after that move.
if [ "$SENDER" = "front_app_switched" ]; then
  moved="$(cat "/tmp/barpopup.$(id -u).moved" 2>/dev/null || echo 0)"
  if [ $(($(date +%s%N) / 1000000 - moved)) -ge 1500 ]; then
    dbg "front app switched -> close"
    sketchybar --set cpu popup.drawing=off --set mem popup.drawing=off --set apple.logo popup.drawing=off
  fi
fi
exit 0
