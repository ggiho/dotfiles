#!/bin/bash
# Pick the AeroSpace binding mode from the focused workspace.
# The terminal workspace gets 'term' (no alt-hjkl) so tmux receives those keys.
TERM_WORKSPACE=8
AEROSPACE=/opt/homebrew/bin/aerospace

ws="${AEROSPACE_FOCUSED_WORKSPACE:-$("$AEROSPACE" list-workspaces --focused 2>/dev/null)}"
prev="$AEROSPACE_PREV_WORKSPACE"

# Only the terminal workspace needs another mode, so a switch that neither leaves nor enters it has
# nothing to change. Skipping it saves a command to AeroSpace on every other switch (measured: the
# switch settles a little sooner; it does not remove the short bounce through the other workspace that
# AeroSpace does when the app it switches to is slow to report its focused window, e.g. DataGrip).
if [ -n "$prev" ] && [ "$ws" != "$TERM_WORKSPACE" ] && [ "$prev" != "$TERM_WORKSPACE" ]; then
  exit 0
fi

if [ "$ws" = "$TERM_WORKSPACE" ]; then
  "$AEROSPACE" mode term
else
  "$AEROSPACE" mode main
fi
