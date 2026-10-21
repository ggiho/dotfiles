#!/bin/bash

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

battery_info="$(pmset -g batt)"
# only the internal battery's line: pmset can list other power sources too (a Bluetooth keyboard or
# AirPods at 80% next to the Mac at 100%), and taking every percentage mixed them up
percentage="$(printf '%s\n' "$battery_info" | grep 'InternalBattery' | grep -Eo '[0-9]+%' | head -1 | cut -d% -f1)"
charging="$(printf '%s' "$battery_info" | grep 'AC Power')"

if ! printf '%s' "$battery_info" | grep -q 'InternalBattery'; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

sketchybar --set "$NAME" drawing=on

if [ -z "$percentage" ]; then
  exit 0
fi

color=$WHITE
case "$percentage" in
  [8-9][0-9]|100)
    icon=$BATTERY_100
    color=$GREEN
    ;;
  [4-7][0-9])
    icon=$BATTERY_75
    color=$YELLOW
    ;;
  [2-3][0-9])
    icon=$BATTERY_25
    color=$ORANGE
    ;;
  *)
    icon=$BATTERY_0
    color=$RED
    ;;
esac

if [ -n "$charging" ]; then
  icon=$BATTERY_CHARGING
fi

sketchybar --set "$NAME" \
           icon="$icon" \
           icon.color="$color" \
           label="${percentage}%"
