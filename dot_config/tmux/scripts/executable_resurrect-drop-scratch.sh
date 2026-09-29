#!/bin/sh
# tmux-resurrect post-save-layout hook: keep the scratch session out of the save file.
#
# scratch backs the Alt-p popup (tmux.conf) and is throwaway. Saved, it came back after
# every tmux restart and turned up among the real sessions. resurrect runs this hook
# before comparing the save with the previous one, so a save that differs only by
# scratch counts as unchanged.
#
# Called by resurrect with the save file as $1.
f=${1:-}
[ -f "$f" ] || exit 0
tmp="$f.drop-scratch.$$"
awk -F'\t' -v OFS='\t' '
  ($1 == "pane" || $1 == "window") && $2 == "scratch" { next }
  $1 == "state" {                       # the sessions the client returns to on restore
    if ($2 == "scratch") $2 = $3
    if ($3 == "scratch") $3 = $2
    if ($2 == "scratch" || $2 == "") next
  }
  { print }' "$f" > "$tmp" && mv "$tmp" "$f"
