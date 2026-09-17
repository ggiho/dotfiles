#!/bin/bash
# macOS notification for Claude Code, labelled with the tmux pane it came from.
#
#   turn-notify.sh start   <- UserPromptSubmit: record when the turn began
#   turn-notify.sh stop    <- Stop: "done", if the turn was slow and its pane is off screen
#   turn-notify.sh ask     <- Notification: "needs you", immediately, if its pane is off screen
#   turn-notify.sh probe   <- diagnostics only: log what the hook received
#
# Env knobs:
#   CLAUDE_NOTIFY_MIN_SECONDS  don't announce turns shorter than this (default 30; stop only)
#   CLAUDE_NOTIFY_SOUND        sound for "done"      (default Glass; empty for silent)
#   CLAUDE_NOTIFY_ASK_SOUND    sound for "needs you" (default Ping;  empty for silent)

set -u

MIN_SECONDS="${CLAUDE_NOTIFY_MIN_SECONDS:-30}"
STATE_DIR="${TMPDIR:-/tmp}/claude-turn-notify"
LOG="$HOME/.claude/hooks/turn-notify.log"
mode="${1:-stop}"

payload=$(cat 2>/dev/null || true)
session=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -n "$session" ] || session=nosession
session=$(printf '%s' "$session" | tr -c 'A-Za-z0-9._-' '_')
stamp="$STATE_DIR/$session"

log() {
  printf '%s [%s] %s\n' "$(date '+%F %T')" "$mode" "$1" >> "$LOG" 2>/dev/null
  # keep the log bounded; it is a debugging aid, not a record
  if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 800 ]; then
    tail -400 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
  fi
}

case "$mode" in
  start)
    mkdir -p "$STATE_DIR" 2>/dev/null && date +%s > "$stamp" 2>/dev/null
    exit 0 ;;
  probe)
    log "stdin=${#payload}B session=$session TMUX_PANE=${TMUX_PANE:-UNSET} payload=$payload"
    exit 0 ;;
esac

# ---------------------------------------------------------------- message body
if [ "$mode" = ask ]; then
  SOUND="${CLAUDE_NOTIFY_ASK_SOUND-Ping}"
  body=$(printf '%s' "$payload" | jq -r '.message // empty' 2>/dev/null || true)
  [ -n "$body" ] || body="입력을 기다리는 중"
else
  SOUND="${CLAUDE_NOTIFY_SOUND-Glass}"
  # gate 1: only announce turns slow enough to be worth interrupting for
  started=$(cat "$stamp" 2>/dev/null || true)
  rm -f "$stamp" 2>/dev/null
  [ -n "$started" ] || { log "skip: no stamp (clear/compact/resume)"; exit 0; }
  elapsed=$(( $(date +%s) - started ))
  [ "$elapsed" -ge "$MIN_SECONDS" ] || { log "skip: ${elapsed}s < ${MIN_SECONDS}s"; exit 0; }
  if [ "$elapsed" -ge 60 ]; then dur="$(( elapsed / 60 ))m $(( elapsed % 60 ))s"
  else dur="${elapsed}s"; fi
  body="작업 완료 · $dur"
fi

cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$cwd" ] && body="$(basename "$cwd") — $body"

# ------------------------------------------------------- pane label + gate 2
subtitle=""; jump=""
if [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then
  fields=$(tmux display-message -p -t "$TMUX_PANE" \
    '#{session_name}|#{window_index}|#{pane_index}|#{window_name}|#{window_active}|#{pane_active}|#{window_zoomed_flag}' \
    2>/dev/null || true)
  if [ -n "$fields" ]; then
    IFS='|' read -r sess win pane winname win_active pane_active zoomed <<<"$fields"
    subtitle="$sess:$win.$pane"
    [ -n "$winname" ] && [ "$winname" != "$sess" ] && subtitle="$subtitle ($winname)"

    # gate 2: is this pane already on screen, in the app the user is looking at?
    # Needs a client attached to THIS session — window_active is only true within it.
    #
    # On screen does NOT mean focused: in a split window every pane is visible, so a
    # pane you can read is not worth a notification even when the cursor is elsewhere.
    # The exception is zoom — a zoomed pane hides its siblings, so an unfocused pane in
    # a zoomed window is genuinely off screen.
    onscreen=0
    if [ "$win_active" = 1 ] && { [ "$pane_active" = 1 ] || [ "${zoomed:-0}" != 1 ]; }; then
      onscreen=1
    fi
    clients=$(tmux list-clients -t "$sess" -F '#{client_pid}' 2>/dev/null || true)
    front=$(lsappinfo info -only pid "$(lsappinfo front 2>/dev/null)" 2>/dev/null |
            sed -n 's/.*"pid"=\([0-9]\{1,\}\).*/\1/p')
    log "gate2 $subtitle win_active=$win_active pane_active=$pane_active zoomed=${zoomed:-?} onscreen=$onscreen clients=[$(printf '%s' "$clients" | tr '\n' ',')] front=${front:-NONE}$([ -n "${front:-}" ] && printf ' (%s)' "$(lsappinfo info -only bundleID "$front" 2>/dev/null | sed -n 's/.*="\(.*\)"/\1/p')")"
    if [ "$onscreen" = 1 ] && [ -n "$clients" ]; then
      if [ -n "$front" ]; then
        while read -r cpid; do
          [ -n "$cpid" ] || continue
          p=$cpid
          while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
            [ "$p" = "$front" ] && { log "skip: $subtitle is on screen"; exit 0; }
            p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
          done
        done <<<"$clients"
      fi
    fi

    jump="$HOME/.claude/hooks/tmux-jump.sh $TMUX_PANE"
  fi
fi

# ------------------------------------------------------------------- deliver
[ "$mode" = ask ] && title="Claude Code — 확인 필요" || title="Claude Code"

notify_osascript() {
  esc() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }
  local s="display notification \"$(esc "$body")\" with title \"$(esc "$title")\""
  [ -n "$subtitle" ] && s="$s subtitle \"$(esc "$subtitle")\""
  [ -n "$SOUND" ] && s="$s sound name \"$(esc "$SOUND")\""
  osascript -e "$s" >/dev/null 2>&1 || true
}

if command -v terminal-notifier >/dev/null 2>&1; then
  args=(-title "$title" -message "$body" -group "claude-$mode-$session")
  [ -n "$subtitle" ] && args+=(-subtitle "$subtitle")
  [ -n "$SOUND" ] && args+=(-sound "$SOUND")
  [ -n "$jump" ] && args+=(-execute "$jump")
  if terminal-notifier "${args[@]}" >/dev/null 2>&1; then log "sent: $subtitle | $body"
  else log "terminal-notifier failed -> osascript"; notify_osascript; fi
else
  log "sent via osascript: $subtitle | $body"
  notify_osascript
fi
exit 0
