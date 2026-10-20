#!/bin/bash

source "$CONFIG_DIR/icons.sh"

update_wifi() {
  local ssid interface hardware_type ip icon label

  ssid="$(/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I 2>/dev/null | awk -F ' SSID: ' '/ SSID: / {print $2}')"
  interface="$(route get default 2>/dev/null | awk '/interface: / {print $2}')"
  hardware_type="$(networksetup -listnetworkserviceorder 2>/dev/null | grep -B 1 "Device: $interface" | head -n 1 | awk '{print $2}')"
  ip="$(ipconfig getifaddr "$interface" 2>/dev/null)"

  if [ "$hardware_type" = "Wi-Fi" ]; then
    icon="$([ -n "$ip" ] && printf '%s' "$WIFI_CONNECTED" || printf '%s' "$WIFI_DISCONNECTED")"
  else
    icon="$([ -n "$ip" ] && printf '%s' "$ETHERNET_CONNECTED" || printf '%s' "$WIFI_DISCONNECTED")"
  fi

  label="$([ -n "$ip" ] && printf '%s (%s)' "${ssid:-Connected}" "$ip" || printf 'Disconnected')"

  sketchybar --set "$NAME" icon="$icon" label="$label"
}

toggle_wifi_label() {
  local current_width new_width
  current_width="$(sketchybar --query "$NAME" | jq -r '.label.width')"
  new_width=0
  if [ "$current_width" = "0" ]; then
    new_width=dynamic
  fi

  sketchybar --animate sin 20 --set "$NAME" label.width="$new_width"
}

case "$SENDER" in
  mouse.clicked) toggle_wifi_label ;;
  *) update_wifi ;;
esac
