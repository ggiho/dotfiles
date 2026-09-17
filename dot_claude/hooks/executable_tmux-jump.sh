#!/bin/bash
# Focus a tmux pane and raise the terminal app hosting it.
# Click action for the notification posted by turn-notify.sh.
#
# macOS relaunches terminal-notifier to run this, so the environment is the GUI
# minimum: PATH is /usr/bin:/bin and Homebrew is not on it. Everything this needs
# is therefore resolved by absolute path, not inherited.
set -u

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
LOG="${HOME:-/tmp}/.claude/hooks/turn-notify.log"
log() { printf '%s [jump] %s\n' "$(date '+%F %T')" "$1" >> "$LOG" 2>/dev/null; }

pane="${1:-}"
[ -n "$pane" ] || { log "no pane argument"; exit 0; }

TMUX_BIN=$(command -v tmux 2>/dev/null)
for c in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
  [ -n "$TMUX_BIN" ] && break
  [ -x "$c" ] && TMUX_BIN=$c
done
[ -n "$TMUX_BIN" ] || { log "tmux not found (PATH=$PATH)"; exit 1; }

sess=$("$TMUX_BIN" display-message -p -t "$pane" '#{session_name}' 2>/dev/null || true)
[ -n "$sess" ] || { log "pane $pane no longer exists"; exit 0; }

# Take the most recently active client, whatever session it is currently showing —
# a pane worth jumping to is usually in a session nobody is attached to.
line=$("$TMUX_BIN" list-clients -F '#{client_activity} #{client_pid} #{client_name}' 2>/dev/null |
       sort -rn | head -1)
cpid=$(printf '%s\n' "$line" | awk '{print $2}')
cname=$(printf '%s\n' "$line" | awk '{print $3}')

[ -n "$cname" ] && "$TMUX_BIN" switch-client -c "$cname" -t "$sess" 2>/dev/null
"$TMUX_BIN" select-window -t "$pane" 2>/dev/null
"$TMUX_BIN" select-pane -t "$pane" 2>/dev/null

# raise whichever app owns that client's tty, so the pane is actually on screen
app=""
p="$cpid"
while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
  b=$(/usr/bin/lsappinfo info -only bundleID "$p" 2>/dev/null |
      /usr/bin/sed -n 's/.*"CFBundleIdentifier"="\([^"]*\)".*/\1/p')
  [ -n "$b" ] && { app=$b; /usr/bin/open -b "$b" 2>/dev/null; break; }
  p=$(/bin/ps -o ppid= -p "$p" 2>/dev/null | /usr/bin/tr -d ' ')
done

log "jumped to $sess / $pane via client=${cname:-none} app=${app:-none}"
exit 0
