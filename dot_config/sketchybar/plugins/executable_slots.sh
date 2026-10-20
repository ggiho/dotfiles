#!/bin/bash
# Creates the app-icon slot items used by the workspace bar (sourced by sketchybarrc).
# Slots stay hidden until helper/wsbar.py fills them; it adds more on demand using the same
# properties (keep the two in sync: see Bar.add_slot in wsbar.py).
#   add_slot <workspace> <index>

add_slot() {
  local ws="$1" n="$2"
  sketchybar --add item "wsapp.$ws.$n" left \
             --set "wsapp.$ws.$n" \
                   drawing=off \
                   updates=off \
                   icon=" " \
                   icon.width=26 \
                   icon.padding_left=1 \
                   icon.padding_right=1 \
                   icon.background.drawing=on \
                   icon.background.image.scale=0.85 \
                   label.drawing=off \
                   padding_left=1 \
                   padding_right=1 \
                   background.drawing=off \
                   background.height=28 \
                   background.corner_radius=7 \
                   background.color=0x33ffffff \
                   background.border_color="$WHITE"
}
