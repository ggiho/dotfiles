#!/bin/bash

# Key repeat
defaults write -g InitialKeyRepeat -int 12
defaults write -g KeyRepeat -int 3
defaults write -g ApplePressAndHoldEnabled -bool false

# Trackpad
defaults write -g com.apple.trackpad.scaling -float 2

# Dock
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock tilesize -int 51

# Finder
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool false

# Dark mode
defaults write -g AppleInterfaceStyle -string "Dark"

# Restart affected apps
killall Dock 2>/dev/null
killall Finder 2>/dev/null
