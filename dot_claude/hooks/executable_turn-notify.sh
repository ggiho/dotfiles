#!/bin/bash
# macOS notification for Claude Code, labelled with the tmux pane it came from.
#
#   turn-notify.sh start   <- UserPromptSubmit: start the clock, disarm any pending notice
#   turn-notify.sh stop    <- Stop: arm a completion notice (does NOT notify yet)
#   turn-notify.sh fail    <- StopFailure: arm a notice marked as an aborted turn
#   turn-notify.sh ask     <- Notification: deliver the armed notice, or a real prompt
#   turn-notify.sh end     <- SessionEnd: drop this session's pending and parked notices
#   turn-notify.sh watch   <- (internal) detached follow-up, see below
#   turn-notify.sh probe   <- diagnostics only: log what the hook received
#
# Stop means "the turn ended", not "the work is done". Claude routinely ends a turn after
# launching background work — agents, background commands, Monitors — and is woken by a
# <task-notification> when each one finishes, often for several rounds per request. So
# Stop only arms, and a notice goes out once Claude Code reports the session idle
# ("waiting for your input", ~60s later) AND nothing launched since your prompt is still
# running. Claude Code's idle signal alone does not mean that: it fired with a background
# sweep still running, and it stays silent at other times with nothing running at all.
#
# While work is in flight the notice is parked with your prompt and its start time. The
# turn that the last piece of work wakes carries it home, so one request yields one
# notice, timed from your prompt. A detached watcher covers what the hooks cannot see:
#   - ~189s after an idle turn Claude Code writes an away_summary recap (what was done,
#     what it needs from you). The watcher swaps it in as the notice's body while the
#     notice is still in Notification Center, or delivers it if the idle signal never came.
#   - a parked notice whose work ended without waking the session (a dead agent) is
#     released by the watcher after a grace period.
#
# Env knobs:
#   CLAUDE_NOTIFY_MIN_SECONDS  don't announce requests shorter than this, timed from your prompt (default 30)
#   CLAUDE_NOTIFY_SOUND        sound for "done"      (default Glass; empty for silent)
#   CLAUDE_NOTIFY_ASK_SOUND    sound for "needs you" (default Ping;  empty for silent)
#   CLAUDE_NOTIFY_PENDING_TTL  drop an armed notice older than this (default 900s)
#   CLAUDE_NOTIFY_BG_STALE     an agent silent for longer than this is presumed dead (default 900s)
#   CLAUDE_NOTIFY_BG_MAX_HOLD  stop waiting for background work after this long (default 7200s)
#   CLAUDE_NOTIFY_RECAP        0 disables the recap swap and fallback (default 1)
#   CLAUDE_NOTIFY_LOG          log path (default ~/.claude/hooks/turn-notify.log)
#   CLAUDE_NOTIFY_DRY_RUN      1 logs every decision but posts nothing — use it for tests,
#                              which otherwise put their notices on the real screen
#   CLAUDE_NOTIFY_HOLD_TICK / CLAUDE_NOTIFY_HOLD_GRACE   watcher cadence (default 30s / 90s)

set -u

MIN_SECONDS="${CLAUDE_NOTIFY_MIN_SECONDS:-30}"
PENDING_TTL="${CLAUDE_NOTIFY_PENDING_TTL:-900}"
BG_STALE="${CLAUDE_NOTIFY_BG_STALE:-900}"
BG_MAX_HOLD="${CLAUDE_NOTIFY_BG_MAX_HOLD:-7200}"
RECAP="${CLAUDE_NOTIFY_RECAP:-1}"
HOLD_TICK="${CLAUDE_NOTIFY_HOLD_TICK:-30}"
HOLD_GRACE="${CLAUDE_NOTIFY_HOLD_GRACE:-90}"
STATE_DIR="${TMPDIR:-/tmp}/claude-turn-notify"
LOG="${CLAUDE_NOTIFY_LOG:-$HOME/.claude/hooks/turn-notify.log}"
DRY_RUN="${CLAUDE_NOTIFY_DRY_RUN:-0}"
IDLE_MSG="Claude is waiting for your input"
mode="${1:-stop}"

if [ "$mode" = watch ]; then payload=""; session="${2:-nosession}"
else
  payload=$(cat 2>/dev/null || true)
  session=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)
fi
[ -n "$session" ] || session=nosession
session=$(printf '%s' "$session" | tr -c 'A-Za-z0-9._-' '_')

# per-session state
turns="$STATE_DIR/$session.t"          # one file per turn begun and not yet ended: .t.EPOCH.PID
legacy_stamp="$STATE_DIR/$session"     # (the single start stamp this used to keep)
pending="$STATE_DIR/$session.pending"  # armed notice: armed_at started dur status task
                                       # (.pending.claimed.PID while one process decides on it)
ctx="$STATE_DIR/$session.ctx"          # cwd transcript
carry="$STATE_DIR/$session.carry"      # your prompt, held across woken turns: started task
req="$STATE_DIR/$session.req"          # when you typed the request not yet announced: epoch
held="$STATE_DIR/$session.held"        # parked for background work: armed_at
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

# Turn starts are kept one file per turn. With a single stamp, a queued <task-notification>
# could start the next turn (UserPromptSubmit is synchronous) before the previous turn's
# asynchronous Stop hook read the stamp — and that Stop would take the new turn's start.
turn_begin() {  # turn_begin new|cont — a prompt you typed forgets any unfinished turn
  [ "$1" = new ] && rm -f "$turns".* 2>/dev/null
  : > "$turns.$(date +%s).$$"
}
turn_take() {  # the start epoch of the turn this Stop ends, which it closes
  # This turn is the newest one that did not begin in the last 2s: a start younger than
  # that is the next turn, queued behind this one's asynchronous Stop. Anything older is
  # a turn that never reached Stop — you interrupted it (Esc fires no Stop) — so forget it.
  local now f e pick="" first=""
  now=$(date +%s)
  for f in $(/bin/ls -1 "$turns".* 2>/dev/null); do          # oldest first
    e=${f#"$turns".}; e=${e%%.*}
    [ -n "$first" ] || first=$f
    [ "$e" -le $(( now - 2 )) ] && pick=$f
  done
  pick=${pick:-$first}                                       # a turn shorter than 2s
  if [ -z "$pick" ]; then                                    # a turn begun before the upgrade
    f=$(cat "$legacy_stamp" 2>/dev/null) && rm -f "$legacy_stamp" && [ -n "$f" ] && { echo "$f"; return 0; }
    return 1
  fi
  for f in $(/bin/ls -1 "$turns".* 2>/dev/null); do [ "$f" \< "$pick" ] && rm -f "$f"; done
  rm "$pick" 2>/dev/null || return 1                         # another Stop took it
  e=${pick#"$turns".}; echo "${e%%.*}"
}
turn_since() {  # turn_since EPOCH — a turn began at or after EPOCH and has not ended
  local f e
  for f in $(/bin/ls -1 "$turns".* 2>/dev/null); do
    e=${f#"$turns".}; e=${e%%.*}
    [ "$e" -ge "$1" ] && return 0
  done
  return 1
}

# Hooks run as separate processes and overlap: two may act on one armed notice (the idle
# signal and the watcher's fallback), or a new turn may begin while one is deciding. A
# process first claims the notice with an atomic rename; whoever loses the rename backs off.
claim() {
  local c="$pending.claimed.$$"
  mv "$pending" "$c" 2>/dev/null || return 1
  printf '%s' "$c"
}

safe() {  # terminal-notifier reads its options through NSUserDefaults, which takes a value
          # starting with "-" for an option and "(…)"/"{…}" for a plist, leaving the text
          # empty. A zero-width space in front keeps it plain text.
  case "$1" in -*|\(*|\{*|\<*|\"*) printf '\342\200\213%s' "$1" ;; *) printf '%s' "$1" ;; esac
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

running_agents() {  # background agents launched or resumed since EPOCH that are still alive
  local tp=$1 since=${2:-0} dir now id state
  [ -f "$tp" ] || { echo 0; return; }
  dir="${tp%.jsonl}/subagents"; now=$(date +%s)
  scan "$tp" 'Async agent launched successfully' '"resumedAgentId"' '<task-notification>' |
  jq -r '
    def txt: if type == "string" then . elif type == "array" then map(.text? // "") | join("") else "" end;
    select(.type == "user")
    | (try (((.timestamp // "")[:19] + "Z") | fromdateiso8601) catch 0) as $ts
    | .message.content as $c
    | if ($c | type) == "string" then
        select($c | test("<status>"))
        | (try ($c | capture("<task-id>(?<id>[A-Za-z0-9]+)</task-id>").id) catch empty) | "done \(.) 0"
      elif ($c | type) == "array" then
        $c[] | select(.type? == "tool_result") | (.content | txt) as $t
        | if ($t | startswith("Async agent launched successfully")) then
            (try ($t | capture("agentId: (?<id>[A-Za-z0-9]+)").id) catch empty) | "run \(.) \($ts)"
          elif ($t | startswith("{\"success\":true")) then
            (try ($t | capture("\"resumedAgentId\":\"(?<id>[A-Za-z0-9]+)\"").id) catch empty) | "run \(.) \($ts)"
          else empty end
      else empty end' 2>/dev/null |
  # like commands, only agents launched (or resumed) since your prompt hold its notice
  awk -v since="$since" '{ last[$2] = $1; at[$2] = $3 }
       END { for (id in last) if (last[id] == "run" && at[id] >= since) print id }' |
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
    state=$(tail -n 200 "$f" 2>/dev/null | jq -r 'select(.type == "assistant" or .type == "user")
      | if .type == "assistant" and (.message.stop_reason == "end_turn" or .message.stop_reason == "stop_sequence")
        then "finished" else "running" end' 2>/dev/null | tail -1)
    # unreadable (all hook attachments in the window) counts as running; the staleness
    # bound above still releases it
    [ "$state" != finished ] && echo "$id"
  done | wc -l | tr -d ' '
}

running_tasks() {  # background commands and Monitors started since EPOCH, still running
  # Only work launched since your prompt counts: a command left running from before it
  # (a dev server) may never end and must not hold notices.
  #   command: its process keeps the output file open until it exits (lsof) — exact, and
  #            unlike the file's mtime it does not mistake a quiet build for a dead one
  #   Monitor: has no output file while running, but states its lifetime at start
  # Ended = a <task-notification> carrying <status> (Monitor events carry none), whether
  # it reached the conversation or only the queue, or a TaskStop.
  local tp=$1 since=$2 now; now=$(date +%s)
  [ -f "$tp" ] || { echo 0; return; }
  local rows outs=() open="" n=0 kind id val out
  rows=$(scan "$tp" 'in background with ID' 'to the background (ID' 'Monitor started (task' \
                    'Successfully stopped task' '<status>' |
  jq -r --argjson since "$since" '
    def txt: if type == "string" then . elif type == "array" then map(.text? // "") | join("") else "" end;
    def ended: if test("<status>[a-z_]+</status>") then
                 [match("<task-id>([A-Za-z0-9]+)</task-id>"; "g").captures[0].string] | .[] | "done \(.)"
               else empty end;
    if .type == "queue-operation" then (.content // "") | ended
    elif .type == "user" then
      (try (((.timestamp // "")[:19] + "Z") | fromdateiso8601) catch 0) as $ts
      | .message.content as $c
      | if ($c | type) == "string" then $c | ended
        elif ($c | type) == "array" then $c[]
          | if .type? == "text" then (.text // "") | ended
            elif .type? == "tool_result" then (.content | txt) as $t
              | if ($t | startswith("Command running in background with ID: ")) or
                   ($t | startswith("Command did not complete")) then
                  (try ($t | capture("ID: (?<id>[A-Za-z0-9]+)").id) catch empty) as $id
                  | (try ($t | capture("(?<p>/[^ ]+?\\.output)").p) catch "-") as $p
                  | if $ts >= $since then "run \($id) bash \($ts) \($p)" else "old \($id)" end
                elif ($t | startswith("Monitor started (task ")) then
                  (try ($t | capture("task (?<id>[A-Za-z0-9]+)").id) catch empty) as $id
                  | ((try ($t | capture("timeout (?<v>[0-9]+)ms").v | tonumber / 1000) catch null)
                     // (try ($t | capture("expires in (?<v>[0-9]+)m").v | tonumber * 60) catch null)) as $life
                  | if $ts >= $since and $life != null then "run \($id) monitor \($ts + $life)"
                    else "old \($id)" end
                elif ($t | startswith("{\"message\":\"Successfully stopped task: ")) then
                  (try ($t | capture("stopped task: (?<id>[A-Za-z0-9]+)").id) catch empty) | "done \(.)"
                else empty end
            else empty end
        else empty end
    else empty end' 2>/dev/null |
  awk '{ last[$2] = $0 } END { for (id in last) if (last[id] ~ /^run /) print last[id] }')
  [ -n "$rows" ] || { echo 0; return; }
  # lsof reports resolved paths (/private/var/... for /var/...): compare resolved paths
  real() { printf '%s/%s' "$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" "$(basename "$1")"; }
  rows=$(while read -r st id kind val out; do
    [ "$kind" = bash ] && [ -f "$out" ] && out=$(real "$out")
    printf '%s %s %s %s %s\n' "$st" "$id" "$kind" "$val" "$out"
  done <<<"$rows")
  while read -r _ id kind val out; do
    [ "$kind" = bash ] && [ -f "$out" ] && outs+=("$out")
  done <<<"$rows"
  [ ${#outs[@]} -gt 0 ] && open=$(/usr/sbin/lsof -F n -- "${outs[@]}" 2>/dev/null | sed -n 's/^n//p')
  while read -r _ id kind val out; do
    case "$kind" in
      bash)    [ $(( now - val )) -le "$BG_MAX_HOLD" ] && printf '%s\n' "$open" | grep -qxF -- "$out" && n=$((n+1)) ;;
      monitor) [ "$now" -lt "${val%.*}" ] && n=$((n+1)) ;;
    esac
  done <<<"$rows"
  echo "$n"
}

in_flight() {  # in_flight TRANSCRIPT SINCE — "N agent(s), M task(s)" when anything runs
  local a t
  a=$(running_agents "$1" "$2"); t=$(running_tasks "$1" "$2")
  [ "$(( ${a:-0} + ${t:-0} ))" -gt 0 ] && echo "${a:-0} agent(s), ${t:-0} command/monitor(s)"
}

pending_request() {  # what Claude is waiting on: "KIND<TAB>TEXT" from the unanswered tool call
  # A permission prompt's payload only says "Claude needs your permission" — for a
  # question, a plan, and a shell command alike. The transcript already holds the call.
  local tp=$1
  [ -f "$tp" ] || return 0
  # jq -s needs whole records: drop the first line only when tail -c cut into one
  { if [ "$(stat -f %z "$tp" 2>/dev/null || echo 0)" -gt 2000000 ]; then
      tail -c 2000000 "$tp" | tail -n +2; else cat "$tp"; fi; } 2>/dev/null | jq -rs '
    def cut(n): gsub("\\s+"; " ") | if length > n then .[0:n-1] + "…" else . end;
    ([.[] | select(.type == "user") | .message.content | arrays | .[]
       | select(.type? == "tool_result") | .tool_use_id]) as $done
    | [.[] | select(.type == "assistant") | .message.content | arrays | .[]
       | select(.type? == "tool_use") | select(.id as $i | $done | index($i) | not)] | last // empty
    | .input as $in
    | if .name == "AskUserQuestion" then
        "question\t" + (($in.questions[0].question // "") | cut(150))
          + (if ($in.questions | length) > 1 then " (외 \(($in.questions | length) - 1)개)" else "" end)
      elif .name == "ExitPlanMode" then "plan\t계획 승인을 기다리는 중"
      elif .name == "Bash" then "permission\tBash: " + (($in.description // $in.command // "") | cut(110))
      elif ($in.file_path? // null) != null then "permission\t\(.name): " + ($in.file_path | split("/") | last)
      elif ($in.url? // null) != null then "permission\t\(.name): " + ($in.url | cut(100))
      else "permission\t" + (.name | sub("^mcp__"; "") | gsub("__"; " · ")) end' 2>/dev/null
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

park() {  # park CLAIM STARTED TASK WHY — hold a claimed notice until background work ends
  local a; a=$(cut -f1 "$1" 2>/dev/null); rm -f "$1"
  # checking took seconds: a turn that began since this notice was armed owns the session
  if turn_since "${a:-0}"; then log "drop: a new turn began while checking"; return; fi
  [ -f "$carry" ] || printf '%s\t%s\n' "$2" "$3" > "$carry"
  printf '%s\n' "$a" > "$held"
  log "hold: $4"
}

deliver_now() {  # deliver_now CLAIM [RECAP] — hand a claimed notice to ask mode
  # decided: ask mode must not second-guess it — a release after BG_MAX_HOLD would be
  # parked again with nothing left to release it
  jq -n --arg s "$session" --arg c "$(cut -f1 "$ctx" 2>/dev/null)" --arg t "$tp" \
        --arg k "$1" --arg r "${2:-}" --arg m "$IDLE_MSG" \
    '{session_id:$s, cwd:$c, transcript_path:$t, message:$m, decided:true, claim:$k}
     + (if $r != "" then {recap:$r} else {} end)' |
    "$0" ask
}

# ---------------------------------------------------------------- lifecycle
case "$mode" in
  start)
    prompt=$(field '.prompt // .message')
    # Background work reporting back continues your request; anything you typed starts new
    # work. Only a leading tag counts — a prompt that merely quotes one (a pasted log) is yours.
    lead=${prompt#"${prompt%%[![:space:]]*}"}
    case "$lead" in "<task-notification>"*) cont=1 ;; *) cont=0 ;; esac
    if [ "$cont" = 1 ]; then turn_begin cont; else turn_begin new; date +%s > "$req"; fi
    rm -f "$legacy_stamp"
    if [ -f "$pending" ]; then
      rm -f "$pending"
      if [ "$cont" = 1 ]; then log "disarmed (background task reported back)"
      else log "disarmed (new prompt)"; fi
    fi
    # a new turn takes over whatever was parked or waiting for its recap
    rm -f "$sent" "$held"
    [ "$cont" = 1 ] || rm -f "$carry"
    exit 0 ;;

  probe)
    log "stdin=${#payload}B TMUX_PANE=${TMUX_PANE:-UNSET} payload=$payload"
    exit 0 ;;

  end)
    # You closed the session, and its background work died with it. Left alone, a parked
    # notice would see that work "end without waking the session" and announce a finish
    # that never happened. Watchers find their state gone and quit on their next check.
    had=""
    for f in "$pending" "$held" "$carry"; do [ -f "$f" ] && had="$had ${f##*.}"; done
    rm -f "$turns".* "$legacy_stamp" "$pending" "$held" "$carry" "$sent" "$ctx" "$req"
    [ -n "$had" ] && log "session ended ($(field .reason)): dropped$had"
    exit 0 ;;

  stop|fail)
    started=$(turn_take) || { log "skip: no stamp (clear/compact/resume)"; exit 0; }
    # Time your request, not this turn. Claude often launches background work and ends
    # the turn in seconds, then reports in another short turn when woken: judged turn by
    # turn, a ten-minute request never reached MIN_SECONDS. Once announced the request is
    # closed, so a stray late wake-up (a Monitor expiring hours later) is judged on its own.
    r=$(cat "$req" 2>/dev/null || true)
    [ -n "$r" ] && [ "$r" -le "$started" ] && started=$r
    tp=$(transcript)
    task=""
    # a turn woken by background work continues your request: time it from your prompt
    [ -f "$carry" ] && IFS=$'\t' read -r started task < "$carry"
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
    # the watcher must outlive this hook: setsid takes it out of the hook's process group
    if [ -x /usr/bin/perl ]; then
      /usr/bin/perl -MPOSIX -e 'setsid; exec @ARGV' "$0" watch "$session" "$armed_at" \
        </dev/null >/dev/null 2>&1 &
    else
      log "no /usr/bin/perl: watcher started without setsid"
      nohup "$0" watch "$session" "$armed_at" </dev/null >/dev/null 2>&1 &
    fi
    exit 0 ;;

  watch)
    armed_at="${3:-0}"
    # one line per watcher on the way out, so a watcher that never acted can be told
    # apart from one that was killed (a missed recap swap, 2026-09-28, was undiagnosable)
    quit() { log "watch done: $1"; exit 0; }
    for sig in HUP INT TERM; do trap "log 'watch killed by SIG$sig'; exit 1" "$sig"; done
    tp=$(transcript)
    recap_until=$(( $(date +%s) + 360 ))    # the recap lands at ~189s (p90 199s)
    zero_since=""
    while :; do
      now=$(date +%s)
      if [ -f "$pending" ]; then
        # armed, idle signal not yet in. Stay until it resolves — if ask mode parks the
        # notice, this watcher is what re-checks it — and meanwhile try the recap fallback.
        a=$(cut -f1 "$pending" 2>/dev/null)
        [ -n "$a" ] || { sleep 1; continue; }                  # changing under us: look again
        [ "$a" = "$armed_at" ] || quit "a newer turn took over"
        [ $(( now - armed_at )) -le "$PENDING_TTL" ] || quit "armed notice expired unconfirmed"
        sleep 5
        [ "$(cut -f1 "$pending" 2>/dev/null)" = "$armed_at" ] || continue   # re-check after sleep
        [ "$RECAP" != 0 ] && [ "$now" -lt "$recap_until" ] || continue
        r=$(recap_since "$tp" "$armed_at")
        [ -n "$r" ] || continue
        c=$(claim) || continue
        if [ "$(cut -f1 "$c")" != "$armed_at" ]; then mv -n "$c" "$pending" 2>/dev/null; continue; fi
        IFS=$'\t' read -r _ started _ _ task < "$c"
        busy=$(in_flight "$tp" "$started")
        if [ -n "$busy" ]; then park "$c" "$started" "$task" "$busy (no idle signal)"; continue; fi
        log "idle signal missing; recap arrived"
        deliver_now "$c" "$r"; quit "delivered the recap (no idle signal)"

      elif /bin/ls "$pending".claimed.* >/dev/null 2>&1; then
        # another process is deciding on the notice (a few seconds); see what it leaves.
        # A claim older than a minute belongs to a process that died.
        c=$(/bin/ls -1 "$pending".claimed.* 2>/dev/null | head -1)
        [ $(( now - $(stat -f %m "$c" 2>/dev/null || echo 0) )) -lt 60 ] || quit "a claim on the notice was abandoned"
        sleep 1

      elif [ -f "$sent" ]; then
        # delivered: swap in the recap while the notice is still in Notification Center
        IFS=$'\t' read -r s_at group title subtitle jump < "$sent"
        [ "$s_at" = "$armed_at" ] || quit "a newer notice was sent"
        [ "$RECAP" != 0 ] && [ "$now" -lt "$recap_until" ] || quit "no recap within 6 min"
        sleep 5
        r=$(recap_since "$tp" "$armed_at")
        [ -n "$r" ] || continue
        # the rename is the claim: a new turn (start mode drops $sent) or a newer notice wins
        mv "$sent" "$sent.claimed.$$" 2>/dev/null || quit "notice taken over by a new turn"
        if [ "$(cut -f1 "$sent.claimed.$$")" != "$armed_at" ]; then
          mv -n "$sent.claimed.$$" "$sent" 2>/dev/null; quit "a newer notice was sent"
        fi
        rm -f "$sent.claimed.$$"
        [ "$DRY_RUN" = 1 ] && quit "recap swapped in (dry-run): $r"
        # clicked or dismissed means you have seen it; re-posting would pop it back up
        terminal-notifier -list "$group" 2>/dev/null | tail -n +2 | grep -q . ||
          quit "recap ready but notice already dismissed"
        args=(-title "$title" -message "$(safe "$r")" -group "$group")
        [ -n "$subtitle" ] && args+=(-subtitle "$(safe "$subtitle")")
        [ -n "$jump" ] && args+=(-execute "$jump")
        terminal-notifier "${args[@]}" >/dev/null 2>&1 && quit "recap swapped in: $r"
        quit "recap swap failed"

      elif [ "$(cat "$held" 2>/dev/null)" = "$armed_at" ]; then
        # parked. Normally the turn that background work wakes takes over (start mode
        # drops $held). Release it here only when the work has ended and the session
        # stayed asleep for a grace period — a dead agent — or the wait ran too long.
        sleep "$HOLD_TICK"
        [ "$(cat "$held" 2>/dev/null)" = "$armed_at" ] || quit "parked notice taken over by a new turn"
        IFS=$'\t' read -r started task < "$carry" 2>/dev/null || quit "parked notice lost its prompt"
        now=$(date +%s)
        if [ $(( now - started )) -ge "$BG_MAX_HOLD" ]; then
          reason="waited $(humanize $(( now - started ))) for background work"
        elif [ -n "$(in_flight "$tp" "$started")" ]; then
          zero_since=""; continue
        else
          zero_since="${zero_since:-$now}"
          [ $(( now - zero_since )) -ge "$HOLD_GRACE" ] || continue
          reason="background work ended without waking the session"
        fi
        rm "$held" 2>/dev/null || quit "parked notice taken over by a new turn"
        c="$pending.claimed.$$"
        printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$started" "$(humanize $(( now - started )))" done "$task" > "$c"
        log "release: $reason"
        deliver_now "$c" "$(recap_since "$tp" "$armed_at")"; quit "released the parked notice"

      else
        quit "nothing left to do (disarmed or suppressed)"
      fi
    done ;;
esac

announced() {  # a completion you were shown (or were looking at) closes the request
  case "${kind:-}" in done|failed) rm -f "$req" ;; esac
}

# ------------------------------------------------------------------ ask mode
message=$(field .message)
recap=$(field .recap)
ntype=$(field .notification_type)
armed_at=""; dur=""
# Route by Claude Code's own notification_type; guessing from the message text is only
# for payloads that lack it. Informational types would be noise: completion is already
# decided here, and auth/quota/computer-use notices need nothing from you.
if [ -z "$ntype" ]; then
  if printf '%s' "$message" | grep -qi 'waiting for your input'; then ntype=idle_prompt
  else ntype=permission_prompt; fi
fi
case "$ntype" in
  idle_prompt|permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input|worker_permission_prompt|push_notification) ;;
  *) log "skip: notification_type=$ntype is informational"; exit 0 ;;
esac

if [ "$ntype" = idle_prompt ]; then
  # Claude Code reports the main loop idle — deliver, unless work is still in flight
  if [ "$(field .decided)" = true ]; then
    c=$(field .claim)                        # the watcher claimed it and has decided
    [ -f "$c" ] || { log "skip: the decided notice vanished"; exit 0; }
  else
    c=$(claim) || { log "skip: idle but nothing armed"; exit 0; }
  fi
  IFS=$'\t' read -r armed_at started dur status task < "$c"
  age=$(( $(date +%s) - ${armed_at:-0} ))
  [ "$age" -le "$PENDING_TTL" ] || { rm -f "$c"; log "skip: armed notice stale (${age}s)"; exit 0; }
  if [ "$(field .decided)" != true ]; then
    busy=$(in_flight "$(transcript)" "${started:-$armed_at}")
    if [ -n "$busy" ]; then park "$c" "$started" "$task" "$busy still running"; exit 0; fi
  fi
  rm -f "$c"
  # checking took seconds: if a turn began since this notice was armed, it is stale
  if turn_since "${armed_at:-0}"; then log "drop: a new turn began while checking"; exit 0; fi
  rm -f "$carry"
  [ "${status:-done}" = failed ] && kind=failed || kind=done
  body="${recap:-$task}"
  if [ "$kind" = failed ]; then SOUND="${CLAUDE_NOTIFY_ASK_SOUND-Ping}"
  else SOUND="${CLAUDE_NOTIFY_SOUND-Glass}"; fi
elif [ "$ntype" = push_notification ]; then
  # Claude chose to reach you: its message is the whole point
  kind=push
  body="${message:-Claude 가 알림을 보냈다}"
  SOUND="${CLAUDE_NOTIFY_ASK_SOUND-Ping}"
else
  # Claude is blocked on you. Say on what, so you can tell from the banner whether to go.
  kind=ask
  req=""
  [ "$ntype" = permission_prompt ] && req=$(pending_request "$(transcript)")
  case "${req%%$'\t'*}" in
    question)   kind=question; body="${req#*$'\t'}" ;;
    plan)       kind=question; body="${req#*$'\t'}" ;;
    permission) body="${req#*$'\t'}" ;;
    *)          body="${message:-입력을 기다리는 중}" ;;
  esac
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
    # Only a focused client counts. WezTerm is frontmost whichever of its tabs you are in,
    # so a tmux client in a background tab would otherwise pass as "on screen" and the
    # notice would vanish. tmux tracks focus from the terminal (focus-events on).
    clients=$(tmux list-clients -t "$sess" -F '#{client_pid} #{client_flags}' 2>/dev/null |
              awk '$2 ~ /(^|,)focused(,|$)/ {print $1}')
    front=$(lsappinfo info -only pid "$(lsappinfo front 2>/dev/null)" 2>/dev/null |
            sed -n 's/.*"pid"=\([0-9]\{1,\}\).*/\1/p')
    log "gate2 $subtitle win_active=$win_active pane_active=$pane_active zoomed=${zoomed:-?} onscreen=$onscreen clients=[$(printf '%s' "$clients" | tr '\n' ',')] front=${front:-NONE}"
    if [ "$onscreen" = 1 ] && [ -n "$clients" ] && [ -n "$front" ]; then
      while read -r cpid; do
        [ -n "$cpid" ] || continue
        p=$cpid
        while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
          [ "$p" = "$front" ] && { log "skip: $subtitle is on screen"; announced; exit 0; }
          p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
        done
      done <<<"$clients"
    fi

    # unquoted on purpose: terminal-notifier does not run -execute through a shell that
    # honours quotes (a quoted path never ran). So $HOME must not contain spaces.
    jump="$HOME/.claude/hooks/tmux-jump.sh $TMUX_PANE"
  fi
fi
if [ -z "$subtitle" ]; then
  # Outside tmux (Claude Desktop, an IDE, a bare terminal) there is no pane to test, so
  # the app hosting this session stands in for the screen: frontmost means you are on it.
  front=$(lsappinfo info -only pid "$(lsappinfo front 2>/dev/null)" 2>/dev/null |
          sed -n 's/.*"pid"=\([0-9]\{1,\}\).*/\1/p')
  p=$PPID
  while [ -n "$front" ] && [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
    [ "$p" = "$front" ] && { log "skip: the app hosting this session is frontmost"; announced; exit 0; }
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  done
fi

# ------------------------------------------------------------------- deliver
case "$kind" in
  question) title="Claude Code — 질문" ;;
  ask)      title="Claude Code — 권한 요청" ;;
  failed)   title="Claude Code — 턴 중단" ;;
  *)        title="Claude Code" ;;
esac

# subtitle carries where and how long; the body carries what the turn was about
meta="$where"
[ -n "$subtitle" ] && meta="${meta:+$meta · }$subtitle"
[ -n "$dur" ] && meta="${meta:+$meta · }$dur"
subtitle="$meta"
[ -n "$body" ] || body=$([ "$kind" = failed ] && echo "턴이 중단됐다" || echo "작업 완료")
group="claude-$kind-$session"
case "$kind" in question|push) group="claude-ask-$session" ;; esac

notify_osascript() {
  esc() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }
  local s="display notification \"$(esc "$body")\" with title \"$(esc "$title")\""
  [ -n "$subtitle" ] && s="$s subtitle \"$(esc "$subtitle")\""
  [ -n "$SOUND" ] && s="$s sound name \"$(esc "$SOUND")\""
  osascript -e "$s" >/dev/null 2>&1 || true
}

announced
if [ "$DRY_RUN" = 1 ]; then
  log "sent[$kind] (dry-run): $subtitle | $body"
  if [ "$kind" = done ] || [ "$kind" = failed ]; then
    [ -z "$recap" ] && [ -n "$armed_at" ] &&
      printf '%s\t%s\t%s\t%s\t%s\n' "$armed_at" "$group" "$title" "$subtitle" "$jump" > "$sent"
  fi
elif command -v terminal-notifier >/dev/null 2>&1; then
  args=(-title "$title" -message "$(safe "$body")" -group "$group")
  [ -n "$subtitle" ] && args+=(-subtitle "$(safe "$subtitle")")
  [ -n "$SOUND" ] && args+=(-sound "$SOUND")
  [ -n "$jump" ] && args+=(-execute "$jump")
  if terminal-notifier "${args[@]}" >/dev/null 2>&1; then
    log "sent[$kind]: $subtitle | $body"
    # leave a note for the watcher so it can swap in the recap later
    if { [ "$kind" = done ] || [ "$kind" = failed ]; } && [ -z "$recap" ] && [ -n "$armed_at" ]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$armed_at" "$group" "$title" "$subtitle" "$jump" > "$sent"
    fi
  else log "terminal-notifier failed -> osascript"; notify_osascript; fi
else
  log "sent[$kind] via osascript: $subtitle | $body"
  notify_osascript
fi
exit 0
