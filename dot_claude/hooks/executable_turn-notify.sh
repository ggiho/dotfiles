#!/bin/bash
# macOS notification for Claude Code, labelled with the tmux pane it came from.
#
#   turn-notify.sh start   <- UserPromptSubmit: start the clock, disarm any pending notice
#   turn-notify.sh stop    <- Stop: arm a completion notice (does NOT notify yet)
#   turn-notify.sh fail    <- StopFailure: arm a notice marked as an aborted turn
#   turn-notify.sh ask     <- Notification: deliver the armed notice, or a real prompt
#   turn-notify.sh watch   <- (internal) wait for Claude Code's recap, see below
#   turn-notify.sh probe   <- diagnostics only: log what the hook received
#
# Stop means "the turn ended", not "the work is done", for two reasons:
#   - a sibling Stop hook can return decision:"block" and keep the turn going;
#   - background agents outlive the turn and, when they finish, wake the session with a
#     <task-notification> prompt. The main loop is genuinely idle in between, so Claude
#     Code's idle signal fires and a "done" notice would be a lie.
# So Stop only arms. Claude Code's idle notification ("waiting for your input", ~60s
# after idle) confirms it, unless an agent launched from this session is still alive —
# then the notice is held and carried to the turn in which the last agent reports back.
#
# Claude Code does watch background *commands*: it withholds the idle signal until they
# end, so its silence is meaningful. It sometimes also stays silent with nothing running.
#
# ~189s after an idle turn Claude Code writes an away_summary recap into the transcript
# (what was done, what it needs from you). A detached watcher swaps the notice's body for
# that recap while it is still in Notification Center. If the idle signal never came, it
# delivers the recap itself — unless a command started this turn is still running, in
# which case the notice is carried to the turn that command's completion wakes.
#
# Env knobs:
#   CLAUDE_NOTIFY_MIN_SECONDS  don't announce turns shorter than this (default 30)
#   CLAUDE_NOTIFY_SOUND        sound for "done"      (default Glass; empty for silent)
#   CLAUDE_NOTIFY_ASK_SOUND    sound for "needs you" (default Ping;  empty for silent)
#   CLAUDE_NOTIFY_PENDING_TTL  drop an armed notice older than this (default 900s)
#   CLAUDE_NOTIFY_BG_STALE     an agent silent for longer than this is presumed dead (default 900s)
#   CLAUDE_NOTIFY_RECAP        0 disables the recap watcher (default 1)
#   CLAUDE_NOTIFY_LOG          log path (default ~/.claude/hooks/turn-notify.log)

set -u

MIN_SECONDS="${CLAUDE_NOTIFY_MIN_SECONDS:-30}"
PENDING_TTL="${CLAUDE_NOTIFY_PENDING_TTL:-900}"
BG_STALE="${CLAUDE_NOTIFY_BG_STALE:-900}"
RECAP="${CLAUDE_NOTIFY_RECAP:-1}"
STATE_DIR="${TMPDIR:-/tmp}/claude-turn-notify"
LOG="${CLAUDE_NOTIFY_LOG:-$HOME/.claude/hooks/turn-notify.log}"
mode="${1:-stop}"

if [ "$mode" = watch ]; then payload=""; session="${2:-nosession}"
else
  payload=$(cat 2>/dev/null || true)
  session=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)
fi
[ -n "$session" ] || session=nosession
session=$(printf '%s' "$session" | tr -c 'A-Za-z0-9._-' '_')

# per-session state
stamp="$STATE_DIR/$session"            # turn start epoch
pending="$STATE_DIR/$session.pending"  # armed notice: armed_at started dur status task
ctx="$STATE_DIR/$session.ctx"          # cwd transcript
carry="$STATE_DIR/$session.carry"      # held for background agents: started task
sent="$STATE_DIR/$session.sent"        # delivered notice, for the recap swap
mkdir -p "$STATE_DIR" 2>/dev/null

log() {
  printf '%s [%s %s] %s\n' "$(date '+%F %T')" "${session:0:8}" "$mode" "$1" >> "$LOG" 2>/dev/null
  if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 800 ]; then
    tail -400 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
  fi
}

field() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null || true; }

humanize() {
  local s=$1
  if   [ "$s" -ge 3600 ]; then echo "$(( s / 3600 ))h $(( s % 3600 / 60 ))m"
  elif [ "$s" -ge 60 ];   then echo "$(( s / 60 ))m $(( s % 60 ))s"
  else echo "${s}s"; fi
}

# ------------------------------------------------------------ transcript reads
# Transcripts reach hundreds of MB (seen: 479MB). A full jq pass took 9s — most of the
# hook's timeout — so every read looks at the tail first and uses rg when it must scan.

transcript() {
  local tp; tp=$(field .transcript_path)
  [ -n "$tp" ] && [ -f "$tp" ] && { printf '%s' "$tp"; return; }
  tp=$(cut -f2 "$ctx" 2>/dev/null)
  [ -n "$tp" ] && [ -f "$tp" ] && { printf '%s' "$tp"; return; }
  /bin/ls -1t "$HOME"/.claude/projects/*/"$session".jsonl 2>/dev/null | head -1
}

scan() {  # scan FILE PATTERN... — matching lines, whole file if rg is available
  local f=$1; shift
  local args=(); for p in "$@"; do args+=(-e "$p"); done
  if command -v rg >/dev/null 2>&1; then rg -N --no-filename -F "${args[@]}" "$f" 2>/dev/null
  else tail -c 8000000 "$f" 2>/dev/null | LC_ALL=C grep -F "${args[@]}"; fi
}

last_prompt() {  # what the turn was about: Claude Code's own last-prompt record
  local tp=$1 line
  [ -f "$tp" ] || return 0
  line=$(tail -c 2000000 "$tp" 2>/dev/null | LC_ALL=C grep -F '"type":"last-prompt"' | tail -1)
  [ -n "$line" ] || line=$(scan "$tp" '"type":"last-prompt"' | tail -1)
  printf '%s' "$line" | jq -r '(.lastPrompt // "") | gsub("\\s+"; " ")
      | if (length > 64) then .[0:63] + "…" else . end' 2>/dev/null
}

running_agents() {  # background agents launched from this session that are still alive
  local tp=$1 dir now id state
  [ -f "$tp" ] || { echo 0; return; }
  dir="${tp%.jsonl}/subagents"; now=$(date +%s)
  scan "$tp" 'Async agent launched successfully' '"resumedAgentId"' '<task-notification>' |
  jq -r '
    def txt: if type == "string" then . elif type == "array" then map(.text? // "") | join("") else "" end;
    select(.type == "user") | .message.content as $c
    | if ($c | type) == "string" then
        select($c | startswith("<task-notification>"))
        | (try ($c | capture("<task-id>(?<id>[A-Za-z0-9]+)</task-id>").id) catch empty) | "done \(.)"
      elif ($c | type) == "array" then
        $c[] | select(.type? == "tool_result") | (.content | txt) as $t
        | if ($t | startswith("Async agent launched successfully")) then
            (try ($t | capture("agentId: (?<id>[A-Za-z0-9]+)").id) catch empty) | "run \(.)"
          elif ($t | startswith("{\"success\":true")) then
            (try ($t | capture("\"resumedAgentId\":\"(?<id>[A-Za-z0-9]+)\"").id) catch empty) | "run \(.)"
          else empty end
      else empty end' 2>/dev/null |
  awk '{ last[$2] = $1 } END { for (id in last) if (last[id] == "run") print id }' |
  while read -r id; do
    # The launch/report bookkeeping alone is not enough: 56 of 93 agents in one session
    # finished without a <task-notification> (their result reached the parent another
    # way). The agent's own transcript is the truth — finished when its last turn ended
    # with end_turn/stop_sequence (trailing hook attachments skipped). An agent that died
    # mid-work (killed, claude restarted) is caught by the staleness bound instead, so a
    # dead agent can never hold notices forever.
    f="$dir/agent-$id.jsonl"
    [ -f "$f" ] || continue
    [ $(( now - $(stat -f %m "$f" 2>/dev/null || echo 0) )) -le "$BG_STALE" ] || continue
    state=$(tail -n 60 "$f" 2>/dev/null | jq -r 'select(.type == "assistant" or .type == "user")
      | if .type == "assistant" and (.message.stop_reason == "end_turn" or .message.stop_reason == "stop_sequence")
        then "finished" else "running" end' 2>/dev/null | tail -1)
    [ "$state" = running ] && echo "$id"
  done | wc -l | tr -d ' '
}

running_bash() {  # background commands started since EPOCH that have not ended
  # Claude Code withholds its idle signal while a background command runs, so its silence
  # is information: the recap fallback must not overrule it. Only commands started during
  # the turn count — one left running from an earlier turn (a dev server) may never end,
  # and Claude Code would then stay silent for good; there the fallback is the only way
  # a notice gets out.
  local tp=$1 since
  [ -f "$tp" ] || { echo 0; return; }
  since=$(date -u -r "$2" '+%Y-%m-%dT%H:%M:%S')
  scan "$tp" 'in background with ID' 'to the background (ID' 'Successfully stopped task' '<task-notification>' |
  jq -r --arg since "$since" '
    def txt: if type == "string" then . elif type == "array" then map(.text? // "") | join("") else "" end;
    def ids: [match("<task-id>([A-Za-z0-9]+)</task-id>"; "g").captures[0].string] | .[];
    if .type == "queue-operation" then (.content // "" | ids) | "done \(.)"
    elif .type == "user" then .message.content as $c | (.timestamp // "")[:19] as $ts
      | if ($c | type) == "string" then ($c | ids) | "done \(.)"
        elif ($c | type) == "array" then $c[]
          | if .type? == "text" then (.text // "" | ids) | "done \(.)"
            elif .type? == "tool_result" then (.content | txt) as $t
              | if ($t | startswith("Command running in background with ID: ")) or
                   ($t | startswith("Command did not complete")) then
                  (try ($t | capture("ID: (?<id>[A-Za-z0-9]+)").id) catch empty)
                  | if $ts >= $since then "run \(.)" else "old \(.)" end
                elif ($t | startswith("{\"message\":\"Successfully stopped task: ")) then
                  (try ($t | capture("stopped task: (?<id>[A-Za-z0-9]+)").id) catch empty) | "done \(.)"
                else empty end
            else empty end
        else empty end
    else empty end' 2>/dev/null |
  awk '{ last[$2] = $1 } END { n = 0; for (id in last) if (last[id] == "run") n++; print n }'
}

recap_since() {  # the away_summary Claude Code wrote after EPOCH, if any
  local tp=$1 iso
  [ -f "$tp" ] || return 0
  iso=$(date -u -r "$2" '+%Y-%m-%dT%H:%M:%S')
  tail -c 1000000 "$tp" 2>/dev/null | LC_ALL=C grep -F '"subtype":"away_summary"' | tail -1 |
    jq -r --arg s "$iso" 'select(.timestamp > $s) | .content // empty
      | sub("\\s*\\(disable recaps in /config\\)\\s*$"; "") | gsub("\\s+"; " ")
      | if (length > 200) then .[0:199] + "…" else . end' 2>/dev/null
}

# ---------------------------------------------------------------- lifecycle
case "$mode" in
  start)
    date +%s > "$stamp"
    prompt=$(field '.prompt // .message')
    if [ -f "$pending" ]; then
      rm -f "$pending"
      case "$prompt" in
        *"<task-notification>"*) log "disarmed (background task reported back)" ;;
        *)                      log "disarmed (new prompt)" ;;
      esac
    fi
    rm -f "$sent"
    # a prompt you typed starts new work; an agent reporting back continues the old one
    case "$prompt" in *"<task-notification>"*) ;; *) rm -f "$carry" ;; esac
    exit 0 ;;

  probe)
    log "stdin=${#payload}B TMUX_PANE=${TMUX_PANE:-UNSET} payload=$payload"
    exit 0 ;;

  stop|fail)
    started=$(cat "$stamp" 2>/dev/null || true)
    rm -f "$stamp"
    [ -n "$started" ] || { log "skip: no stamp (clear/compact/resume)"; exit 0; }
    tp=$(transcript)
    task=""
    if [ -f "$carry" ]; then
      # work held for background agents: measure from the prompt you typed
      IFS=$'\t' read -r started task < "$carry"
    fi
    elapsed=$(( $(date +%s) - started ))
    if [ "$mode" != fail ] && [ ! -f "$carry" ] && [ "$elapsed" -lt "$MIN_SECONDS" ]; then
      log "skip: ${elapsed}s < ${MIN_SECONDS}s"; exit 0
    fi
    [ -n "$task" ] || task=$(last_prompt "$tp")
    [ "$mode" = fail ] && status=failed || status=done
    armed_at=$(date +%s)
    printf '%s\t%s\t%s\t%s\t%s\n' "$armed_at" "$started" "$(humanize "$elapsed")" "$status" "$task" > "$pending"
    printf '%s\t%s\n' "$(field .cwd)" "$tp" > "$ctx"
    log "armed[$status]: $(humanize "$elapsed")$([ -f "$carry" ] && echo ' (carried)')"
    if [ "$RECAP" != 0 ]; then
      /usr/bin/perl -MPOSIX -e 'setsid; exec @ARGV' "$0" watch "$session" "$armed_at" \
        </dev/null >/dev/null 2>&1 &
    fi
    exit 0 ;;

  watch)
    armed_at="${3:-0}"
    tp=$(transcript)
    for _ in $(seq 72); do            # up to 6 min; the recap lands at ~189s (p90 199s)
      sleep 5
      if [ -f "$pending" ]; then
        [ "$(cut -f1 "$pending")" = "$armed_at" ] || exit 0     # superseded by a newer turn
        r=$(recap_since "$tp" "$armed_at")
        [ -n "$r" ] || continue
        IFS=$'\t' read -r _ started _ _ task < "$pending"
        b=$(running_bash "$tp" "${started:-$armed_at}")
        if [ "${b:-0}" -gt 0 ]; then
          # Claude Code is silent because of these: when they finish, the session wakes
          # with a <task-notification>, and that turn carries the notice home
          [ -f "$carry" ] || printf '%s\t%s\n' "$started" "$task" > "$carry"
          rm -f "$pending"
          log "hold: $b background command(s) from this turn still running"
          exit 0
        fi
        # recap written, nothing of this turn still running, yet no idle signal: a miss
        log "idle signal missing; recap arrived"
        jq -n --arg s "$session" --arg c "$(cut -f1 "$ctx" 2>/dev/null)" --arg t "$tp" --arg r "$r" \
          '{session_id:$s, cwd:$c, transcript_path:$t, recap:$r,
            message:"Claude is waiting for your input"}' | "$0" ask
        exit 0
      elif [ -f "$sent" ]; then
        IFS=$'\t' read -r s_at group title subtitle jump < "$sent"
        [ "$s_at" = "$armed_at" ] || exit 0
        r=$(recap_since "$tp" "$armed_at")
        [ -n "$r" ] || continue
        rm -f "$sent"
        # swap only while it is still in Notification Center: clicked or dismissed means
        # you have seen it, and re-posting would pop it back up
        terminal-notifier -list "$group" 2>/dev/null | tail -n +2 | grep -q . ||
          { log "recap ready but notice already dismissed"; exit 0; }
        args=(-title "$title" -message "$r" -group "$group")
        [ -n "$subtitle" ] && args+=(-subtitle "$subtitle")
        [ -n "$jump" ] && args+=(-execute "$jump")
        terminal-notifier "${args[@]}" >/dev/null 2>&1 && log "recap swapped in: $r"
        exit 0
      else
        exit 0                        # disarmed, held, or suppressed
      fi
    done
    rm -f "$sent"
    exit 0 ;;
esac

# ------------------------------------------------------------------ ask mode
message=$(field .message)
recap=$(field .recap)
armed_at=""; dur=""

if printf '%s' "$message" | grep -qi 'waiting for your input'; then
  # Claude Code says the main loop is idle — the armed notice is real, unless agents are
  [ -f "$pending" ] || { log "skip: idle but nothing armed"; exit 0; }
  IFS=$'\t' read -r armed_at started dur status task < "$pending"
  rm -f "$pending"
  age=$(( $(date +%s) - ${armed_at:-0} ))
  [ "$age" -le "$PENDING_TTL" ] || { log "skip: armed notice stale (${age}s)"; exit 0; }

  n=$(running_agents "$(transcript)")
  if [ "${n:-0}" -gt 0 ]; then
    # keep the original start and prompt; the turn the last agent wakes will announce it
    [ -f "$carry" ] || printf '%s\t%s\n' "$started" "$task" > "$carry"
    log "hold: $n background agent(s) still running"
    exit 0
  fi
  rm -f "$carry"
  [ "${status:-done}" = failed ] && kind=failed || kind=done
  body="${recap:-$task}"
  if [ "$kind" = failed ]; then SOUND="${CLAUDE_NOTIFY_ASK_SOUND-Ping}"
  else SOUND="${CLAUDE_NOTIFY_SOUND-Glass}"; fi
else
  # a real prompt: permission request, or anything else Claude Code asks for
  kind=ask
  body="${message:-입력을 기다리는 중}"
  SOUND="${CLAUDE_NOTIFY_ASK_SOUND-Ping}"
fi

cwd=$(field .cwd)
where=""; [ -n "$cwd" ] && where=$(basename "$cwd")

# ------------------------------------------------------- pane label + gate 2
subtitle=""; jump=""
if [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then
  fields=$(tmux display-message -p -t "$TMUX_PANE" \
    '#{pane_id}|#{session_name}|#{window_index}|#{pane_index}|#{window_name}|#{window_active}|#{pane_active}|#{window_zoomed_flag}' \
    2>/dev/null || true)
  IFS='|' read -r pid sess win pane winname win_active pane_active zoomed <<<"$fields"
  # tmux 3.7 answers a query about a closed pane with empty fields and exit 0, not an
  # error — only the echoed pane id tells a live pane from a dead one
  if [ "$pid" = "$TMUX_PANE" ]; then
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
    log "gate2 $subtitle win_active=$win_active pane_active=$pane_active zoomed=${zoomed:-?} onscreen=$onscreen clients=[$(printf '%s' "$clients" | tr '\n' ',')] front=${front:-NONE}"
    if [ "$onscreen" = 1 ] && [ -n "$clients" ] && [ -n "$front" ]; then
      while read -r cpid; do
        [ -n "$cpid" ] || continue
        p=$cpid
        while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
          [ "$p" = "$front" ] && { log "skip: $subtitle is on screen"; exit 0; }
          p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
        done
      done <<<"$clients"
    fi

    jump="$HOME/.claude/hooks/tmux-jump.sh $TMUX_PANE"
  fi
fi

# ------------------------------------------------------------------- deliver
case "$kind" in
  ask)    title="Claude Code — 확인 필요" ;;
  failed) title="Claude Code — 턴 중단" ;;
  *)      title="Claude Code" ;;
esac

# subtitle carries where and how long; the body carries what the turn was about
meta="$where"
[ -n "$subtitle" ] && meta="${meta:+$meta · }$subtitle"
[ -n "$dur" ] && meta="${meta:+$meta · }$dur"
subtitle="$meta"
[ -n "$body" ] || body=$([ "$kind" = failed ] && echo "턴이 중단됐다" || echo "작업 완료")
group="claude-$kind-$session"

notify_osascript() {
  esc() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }
  local s="display notification \"$(esc "$body")\" with title \"$(esc "$title")\""
  [ -n "$subtitle" ] && s="$s subtitle \"$(esc "$subtitle")\""
  [ -n "$SOUND" ] && s="$s sound name \"$(esc "$SOUND")\""
  osascript -e "$s" >/dev/null 2>&1 || true
}

if command -v terminal-notifier >/dev/null 2>&1; then
  args=(-title "$title" -message "$body" -group "$group")
  [ -n "$subtitle" ] && args+=(-subtitle "$subtitle")
  [ -n "$SOUND" ] && args+=(-sound "$SOUND")
  [ -n "$jump" ] && args+=(-execute "$jump")
  if terminal-notifier "${args[@]}" >/dev/null 2>&1; then
    log "sent[$kind]: $subtitle | $body"
    # leave a note for the watcher so it can swap in the recap later
    if [ "$kind" != ask ] && [ -z "$recap" ] && [ -n "$armed_at" ]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$armed_at" "$group" "$title" "$subtitle" "$jump" > "$sent"
    fi
  else log "terminal-notifier failed -> osascript"; notify_osascript; fi
else
  log "sent[$kind] via osascript: $subtitle | $body"
  notify_osascript
fi
exit 0
