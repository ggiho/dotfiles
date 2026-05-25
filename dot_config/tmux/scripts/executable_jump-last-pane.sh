#!/usr/bin/env sh
# Jump to the previously focused pane across all sessions/windows (bound to prefix l)
set -eu

current_pane="$(tmux display-message -p '#{pane_id}')"
last_pane="$(tmux show-option -gqv @global_last_pane 2>/dev/null || true)"

if [ -z "$last_pane" ]; then
  tmux display-message 'No previous pane recorded yet'
  exit 0
fi

if ! tmux list-panes -a -F '#{pane_id}' | grep -Fxq "$last_pane"; then
  tmux display-message 'Previous pane no longer exists'
  tmux set-option -gu @global_last_pane 2>/dev/null || true
  exit 0
fi

tmux set-option -gq @global_last_pane "$current_pane"
tmux set-option -gq @global_current_pane "$last_pane"
tmux switch-client -t "$last_pane"
