#!/usr/bin/env bash
# Cycle tmux sessions in session_id (creation) order.
#
# tmux's built-in `switch-client -p/-n` is hardcoded to *name* order with no
# option to change it, so we resolve the neighbour ourselves. session_id ($1,
# $3, ...) is assigned at creation and never reused, making it tmux's only
# stable "session number".
#
# Usage: session-cycle.sh <next|prev> <client_tty> <current_session_id>
# Set SESSION_CYCLE_DRY=1 to print the target instead of switching.
set -eu

dir=$1
tty=$2
cur=${3#\$}

target=$(tmux list-sessions -F '#{session_id}' | tr -d '$' | sort -n | awk -v cur="$cur" -v dir="$dir" '
  { id[NR] = $1; if ($1 == cur) idx = NR }
  END {
    if (NR <= 1) exit 1                       # nothing to cycle to
    if (!idx) idx = 1                         # current not found: start at first
    t = (dir == "next") ? (idx % NR) + 1 : ((idx + NR - 2) % NR) + 1
    print id[t]
  }
') || exit 0

if [ -n "${SESSION_CYCLE_DRY:-}" ]; then
  tmux list-sessions -F '#{session_id} #{session_name}' | tr -d '$' | awk -v t="$target" '$1==t {print $2}'
else
  tmux switch-client -c "$tty" -t "\$$target"
fi
