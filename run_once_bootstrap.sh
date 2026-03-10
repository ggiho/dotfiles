#!/bin/bash
set -e

# Brewfile로 패키지 설치
if [ -f "$HOME/.config/brew/Brewfile" ]; then
  echo "Installing packages from Brewfile..."
  brew bundle install --file="$HOME/.config/brew/Brewfile"
fi
