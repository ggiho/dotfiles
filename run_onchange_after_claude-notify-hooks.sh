#!/bin/bash
# Wire the macOS notification hooks into ~/.claude/settings.json.
#
# settings.json itself is deliberately NOT tracked: it carries machine-specific
# gateway config (internal hostnames), which must not land in a public repo.
# Only the hook entries are merged in here, idempotently, so a fresh machine gets
# the wiring without the rest of the file.
#
# Scripts: dot_claude/hooks/{turn-notify,tmux-jump}.sh
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
HOOK='"$HOME/.claude/hooks/turn-notify.sh"'

if ! command -v jq >/dev/null 2>&1; then
  echo "chezmoi: jq not found — skipping Claude notification hook wiring" >&2
  exit 0
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"

if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "chezmoi: $SETTINGS is not valid JSON — refusing to touch it" >&2
  exit 1
fi

tmp=$(mktemp)
jq \
  --arg start "$HOOK start" \
  --arg stop  "$HOOK stop" \
  --arg ask   "$HOOK ask" '
  def ensure($event; $cmd; $extra):
    .hooks[$event] = ((.hooks[$event] // [])
      | if any(.[]; (.hooks // []) | any(.command == $cmd))
        then .
        else . + [{hooks: [({type: "command", command: $cmd} + $extra)]}]
        end);
    ensure("UserPromptSubmit"; $start; {timeout: 5})
  | ensure("Stop";             $stop;  {async: true, timeout: 15})
  | ensure("Notification";     $ask;   {async: true, timeout: 15})
' "$SETTINGS" > "$tmp"

if cmp -s "$tmp" "$SETTINGS"; then
  rm -f "$tmp"
else
  mv "$tmp" "$SETTINGS"
  echo "chezmoi: wired Claude notification hooks into $SETTINGS"
fi
