#!/bin/bash
# Pick the AeroSpace binding mode from the focused workspace.
# The terminal workspace gets 'term' (no alt-hjkl) so tmux receives those keys.
TERM_WORKSPACE=2
AEROSPACE=/opt/homebrew/bin/aerospace

ws="${AEROSPACE_FOCUSED_WORKSPACE:-$("$AEROSPACE" list-workspaces --focused 2>/dev/null)}"
if [ "$ws" = "$TERM_WORKSPACE" ]; then
  "$AEROSPACE" mode term
else
  "$AEROSPACE" mode main
fi
