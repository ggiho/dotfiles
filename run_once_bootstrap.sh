#!/bin/bash
set -e

# Homebrew 설치
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# chezmoi 설치
if ! command -v chezmoi &>/dev/null; then
  echo "Installing chezmoi..."
  brew install chezmoi
fi

# Brewfile로 패키지 설치
if [ -f "$HOME/.config/brew/Brewfile" ]; then
  echo "Installing packages from Brewfile..."
  brew bundle install --file="$HOME/.config/brew/Brewfile"
fi
