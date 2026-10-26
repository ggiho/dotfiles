#!/bin/bash

source "$CONFIG_DIR/icons.sh"

current_volume() {
  # Treat muted output as 0 so the icon/label match what the volume_change event reports
  osascript -e 'set s to get volume settings' \
            -e 'if output muted of s is true then return 0' \
            -e 'return output volume of s' 2>/dev/null
}

current_output_icon() {
  if [ "$1" = "0" ]; then
    printf '%s\n' "$VOLUME_0"
    return
  fi

  if command -v SwitchAudioSource >/dev/null 2>&1; then
    local output
    output="$(SwitchAudioSource -t output -c 2>/dev/null)"
    if [[ "$output" == *AirPods* ]]; then
      printf '%s\n' "$AIRPODS"
      return
    fi
    if [[ "$output" == *External* ]] || [[ "$output" == *Headphone* ]]; then
      printf '%s\n' "$HEADPHONES"
      return
    fi
  fi

  case "$1" in
    [6-9][0-9]|100) printf '%s\n' "$VOLUME_100" ;;
    [3-5][0-9]) printf '%s\n' "$VOLUME_66" ;;
    [1-2][0-9]) printf '%s\n' "$VOLUME_33" ;;
    [1-9]) printf '%s\n' "$VOLUME_10" ;;
    0) printf '%s\n' "$VOLUME_0" ;;
    *) printf '%s\n' "$VOLUME_100" ;;
  esac
}

TOKEN_FILE="/tmp/sketchybar-volume.$(id -u)"

apply_volume() {
  local volume="${1:-0}"
  local icon
  local token

  icon="$(current_output_icon "$volume")"

  sketchybar --set volume_icon icon="$icon" label="${volume}%"
  sketchybar --set "$NAME" slider.percentage="$volume"

  # Open it unless it is fully open. A query that fails counts as "not open", so the slider opens anyway.
  if [ "$(sketchybar --query "$NAME" 2>/dev/null | jq -r '.slider.width' 2>/dev/null)" != "100" ]; then
    sketchybar --animate tanh 30 --set "$NAME" slider.width=100
  fi

  # Close it 2 seconds after the LAST change. Which change is the last is decided by a token in a file, not by
  # asking the bar: a query that failed while the bar was busy used to leave the slider open for good.
  token="$$.$RANDOM"
  printf '%s' "$token" > "$TOKEN_FILE"
  (
    sleep 2
    if [ "$(cat "$TOKEN_FILE" 2>/dev/null)" = "$token" ]; then
      sketchybar --animate tanh 30 --set "$NAME" slider.width=0 || { sleep 1; sketchybar --animate tanh 30 --set "$NAME" slider.width=0; }
    fi
  ) &
}

case "$SENDER" in
  volume_change)
    apply_volume "$INFO"
    ;;
  mouse.clicked)
    osascript -e "set volume output volume ${PERCENTAGE:-0}" >/dev/null 2>&1
    apply_volume "${PERCENTAGE:-0}"
    ;;
  *)
    apply_volume "$(current_volume || printf '0')"
    ;;
esac
