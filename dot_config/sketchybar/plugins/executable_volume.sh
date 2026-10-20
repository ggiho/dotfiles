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

apply_volume() {
  local volume="${1:-0}"
  local icon
  local initial_width
  local final_percentage

  icon="$(current_output_icon "$volume")"

  sketchybar --set volume_icon icon="$icon" label="${volume}%"
  sketchybar --set "$NAME" slider.percentage="$volume"

  initial_width="$(sketchybar --query "$NAME" | jq -r '.slider.width')"
  if [ "$initial_width" = "0" ]; then
    sketchybar --animate tanh 30 --set "$NAME" slider.width=100
  fi

  (
    sleep 2
    final_percentage="$(sketchybar --query "$NAME" | jq -r '.slider.percentage')"
    if [ "$final_percentage" = "$volume" ]; then
      sketchybar --animate tanh 30 --set "$NAME" slider.width=0
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
