#!/bin/bash
# Click on the cpu, mem or apple.logo item of the bar:   barpopup.sh <cpu|mem|apple.logo>
#   left click   popup, measured right now (nothing refreshes it while it is open); click again to close
#                  cpu: busy, user/system, load average, top apps
#                  mem: used, app/wired/compressed, swap, pressure, top apps
#                  apple.logo: its menu (static rows)
#   right click  (cpu, mem) open Activity Monitor

kind="$1"
case "$kind" in
  cpu) others="mem apple.logo" ;;
  mem) others="cpu apple.logo" ;;
  apple.logo) others="cpu mem" ;;
  *) exit 1 ;;
esac

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"
AERO=/opt/homebrew/bin/aerospace
HELPER="$CONFIG_DIR/helper/sysstat"
SEQ="/tmp/barpopup.$(id -u).seq"

# (debug) touch /tmp/wsbar-debug-on to log what every click did to /tmp/barpopup.log
dbg() { [ -e /tmp/wsbar-debug-on ] && echo "$(date +%T.%N | cut -c1-12) $*" >> /tmp/barpopup.log; }

if [ "$BUTTON" = "right" ] && [ "$kind" != "apple.logo" ]; then
  open -a "Activity Monitor"
  sketchybar --set cpu popup.drawing=off --set mem popup.drawing=off
  exit 0
fi

# Every click (and every mouse-exit close, see popupevents.sh) takes a new number. Opening takes a moment,
# so an open that was overtaken by a later click must not show the popup late, on whatever display
# happens to be focused by then.
seq=$(($(cat "$SEQ" 2>/dev/null || echo 0) + 1))
echo "$seq" > "$SEQ"

if sketchybar --query "$kind" | grep -A6 '"popup"' | grep -q '"drawing": "on"'; then
  dbg "$kind click #$seq -> close"
  sketchybar --set "$kind" popup.drawing=off
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

color_for() {   # <value> <yellow from> <red from>
  if [ "$1" -ge "$3" ]; then echo "$CAT_RED"; elif [ "$1" -ge "$2" ]; then echo "$CAT_YELLOW"; else echo "$CAT_BLUE"; fi
}
shorten() {   # the name column is about 20 characters wide
  if [ "${#1}" -gt 20 ]; then echo "${1:0:19}…"; else echo "$1"; fi
}

# ---- what to measure (started in the background while the focus moves) ------------------------------
# Apps are summed per .app (Chrome's helper processes count for Chrome). Output: "<value>\t<name>".
apps_by() {   # <ps column> <awk expression turning the summed column into the printed value>
  ps -Ao "$1=,comm=" | awk -v n="$(sysctl -n hw.ncpu)" '
    { v = $1; sub(/^ *[0-9.]+ +/, ""); path = $0
      if (match(path, /[^\/]+\.app/)) name = substr(path, RSTART, RLENGTH - 4)
      else { k = split(path, a, "/"); name = a[k] }
      sum[name] += v }
    END { for (k in sum) printf "%.1f\t%s\n", '"$2"', k }' | sort -rn | head -8
}

start_cpu() {
  "$HELPER" --split > "$tmp/split" &
  sysctl -n hw.ncpu vm.loadavg > "$tmp/sys" &
  apps_by pcpu 'sum[k] / n' > "$tmp/apps" &       # share of the whole machine, a recent average
}
start_apple() { :; }
start_mem() {
  "$HELPER" --mem > "$tmp/mem" &
  apps_by rss 'sum[k] / 1024' > "$tmp/apps" &     # resident MB; shared pages are counted per app
}

# ---- turn the measurements into sketchybar arguments (array "args") -----------------------------------
fill_apps() {   # <item prefix> <label formatter: cpu|mem>
  local i=0 top="" pct name rel
  while IFS=$'\t' read -r pct name; do
    [ -n "$name" ] || continue
    i=$((i + 1))
    [ -n "$top" ] || top="${pct%.*}"
    [ "${top:-0}" -ge 1 ] || top=1
    rel=$(((${pct%.*} * 10 + ${pct#*.}) * 100 / (top * 10)))
    [ "$rel" -le 100 ] || rel=100
    if [ "$2" = cpu ]; then
      label="${pct}%"; color="$(color_for "${pct%.*}" 15 30)"
    else
      label="$(awk -v m="$pct" 'BEGIN { if (m >= 1024) printf "%.1fG", m / 1024; else printf "%dM", m }')"; color=$CAT_BLUE
    fi
    args+=(--set "$1.app.$i" drawing=on icon="$(shorten "$name")" label="$label" slider.percentage="$rel" slider.highlight_color="$color")
  done < "$tmp/apps"
  local j
  for ((j = i + 1; j <= 8; j++)); do args+=(--set "$1.app.$j" drawing=off); done
}

build_cpu() {
  local user sys busy load
  read -r user sys < "$tmp/split"
  [ -n "$user" ] || exit 0
  busy=$((user + sys))
  load="$(sed -n 2p "$tmp/sys" | tr -d '{}' | awk '{printf "%.1f  %.1f  %.1f", $1, $2, $3}')"
  args=(--set cpu.popup.usage slider.percentage="$busy" label="${busy}%" slider.highlight_color="$(color_for "$busy" 60 85)"
        --set cpu.popup.user slider.percentage="$user" label="${user}%" slider.highlight_color="$(color_for "$user" 60 85)"
        --set cpu.popup.sys slider.percentage="$sys" label="${sys}%" slider.highlight_color="$(color_for "$sys" 60 85)"
        --set cpu.popup.load label="$load")
  fill_apps cpu.popup cpu
}

build_apple() { args=(); }

build_mem() {
  local used app wired comp total swap pressure pcol ptxt
  read -r used app wired comp total swap pressure < "$tmp/mem"
  [ -n "$used" ] || exit 0
  case "$pressure" in
    4) pcol=$CAT_RED; ptxt=Critical ;;
    2) pcol=$CAT_YELLOW; ptxt=Warning ;;
    *) pcol=$CAT_GREEN; ptxt=Normal ;;
  esac
  local g_used g_app g_wired g_comp g_swap g_total
  read -r g_used g_app g_wired g_comp g_swap g_total < <(awk -v a="$used" -v b="$app" -v c="$wired" -v d="$comp" -v e="$swap" -v f="$total" \
    'BEGIN { printf "%.1f %.1f %.1f %.1f %.1f %.0f", a/1024, b/1024, c/1024, d/1024, e/1024, f/1024 }')
  args=(--set mem.popup.used icon="Used of ${g_total}G" slider.percentage=$((used * 100 / total)) label="${g_used}G" slider.highlight_color="$pcol"
        --set mem.popup.app slider.percentage=$((app * 100 / total)) label="${g_app}G"
        --set mem.popup.wired slider.percentage=$((wired * 100 / total)) label="${g_wired}G"
        --set mem.popup.comp slider.percentage=$((comp * 100 / total)) label="${g_comp}G"
        --set mem.popup.swap label="${g_swap}G" label.color="$(color_for $((swap / 1024)) 2 5)"
        --set mem.popup.pressure label="$ptxt" label.color="$pcol")
  fill_apps mem.popup mem
}

"start_$kind"

# SketchyBar draws a popup on the display that has the macOS focus, not on the one that was clicked
# (SketchyBar issue #742), so bring the focus to the monitor under the pointer while the measuring runs.
$AERO list-monitors --focused --format '%{monitor-id}' > "$tmp/focused" &
clicked="$("$HELPER" --mouse)"
wait $!
if [ -n "$clicked" ] && [ "$clicked" != "$(cat "$tmp/focused")" ]; then
  # remember when we moved the focus ourselves, so popupevents.sh does not take its event for the user's
  echo $(($(date +%s%N) / 1000000)) > "/tmp/barpopup.$(id -u).moved"
  $AERO focus-monitor "$clicked" && sleep 0.1
fi
wait

args=()
"build_$kind"

# a later click or a mouse exit took over while this was preparing: do not show a stale popup
if [ "$(cat "$SEQ" 2>/dev/null)" != "$seq" ]; then
  dbg "$kind click #$seq -> open abandoned (overtaken by #$(cat "$SEQ"))"
  exit 0
fi
dbg "$kind click #$seq -> open on monitor ${clicked:-?}"
off=()
for o in $others; do off+=(--set "$o" popup.drawing=off); done
sketchybar "${args[@]}" "${off[@]}" --set "$kind" popup.drawing=on 2>/dev/null

# Nobody may be around to close it (a mouse exit is not reliable), so it closes by itself, unless a
# later click or close took over in the meantime.
(
  sleep 20
  if [ "$(cat "$SEQ" 2>/dev/null)" = "$seq" ]; then
    dbg "$kind click #$seq -> auto close"
    sketchybar --set cpu popup.drawing=off --set mem popup.drawing=off --set apple.logo popup.drawing=off
  fi
) > /dev/null 2>&1 &
disown
