#!/bin/bash

# Static palette inspired by the referenced felixkratz-linkarzu setup.
# The original repo sources an external colorscheme file; this local copy keeps
# the same dark translucent look without requiring that dependency.

export BLACK=0xff181926
export WHITE=0xffebfafa
export RED=0xfff16c75
export GREEN=0xff37f499
export BLUE=0xff04d1f9
export YELLOW=0xfff1fc79
export ORANGE=0xfff7c67f
export MAGENTA=0xffa48cf2
export GREY=0xff7f8490
export TRANSPARENT=0x00000000

export BG0=0xff0d1116
export BG0O85=0xe60d1116
export BG1=0xcc2a2d3a
export BG2=0xcc494d64

export BAR_COLOR=$BG0O85
export BAR_BORDER_COLOR=$BG2
export BACKGROUND_1=$BG1
export BACKGROUND_2=$BG2
export ICON_COLOR=$WHITE
export LABEL_COLOR=$WHITE
export POPUP_BACKGROUND_COLOR=$BG0O85
export POPUP_BORDER_COLOR=$BG2

# Catppuccin Mocha, used by the CPU popup only (the bar keeps the palette above)
export CAT_BASE=0xb31e1e2e
export CAT_SURFACE1=0xff45475a
export CAT_SURFACE2=0xff585b70
export CAT_OVERLAY1=0xff7f849c
export CAT_SUBTEXT0=0xffa6adc8
export CAT_TEXT=0xffcdd6f4
export CAT_BLUE=0xff89b4fa
export CAT_MAUVE=0xffcba6f7
export CAT_GREEN=0xffa6e3a1
export CAT_YELLOW=0xfff9e2af
export CAT_RED=0xfff38ba8
