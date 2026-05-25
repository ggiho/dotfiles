#!/usr/bin/env sh
# Record pane focus changes for global last-pane jumping (called via tmux hook)
set -eu

new_pane="${1:-}"
[ -n "$new_pane" ] || exit 0

current_pane="$(tmux show-option -gqv @global_current_pane 2>/dev/null || true)"

[ "$new_pane" != "$current_pane" ] || exit 0

if [ -n "$current_pane" ]; then
  tmux set-option -gq @global_last_pane "$current_pane"
fi

tmux set-option -gq @global_current_pane "$new_pane"
