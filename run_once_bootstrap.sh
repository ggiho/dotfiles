#!/bin/bash
set -e

# Brewfile로 패키지 설치
if [ -f "$HOME/.config/brew/Brewfile" ]; then
  echo "Installing packages from Brewfile..."
  brew bundle install --file="$HOME/.config/brew/Brewfile"
fi

# TPM (Tmux Plugin Manager)
if [ ! -d "$HOME/.config/tmux/.tmux/plugins/tpm" ]; then
  echo "Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/.tmux/plugins/tpm
fi

echo "Installing tmux plugins..."
~/.config/tmux/.tmux/plugins/tpm/bin/install_plugins

# kanata (keyboard remapper) 설정
if command -v kanata &>/dev/null && [ -f "$HOME/.config/kanata/scripts/install-launchd.sh" ]; then
  echo "Installing Kanata VirtualHIDDevice and launchd services..."
  sudo "$HOME/.config/kanata/scripts/install-launchd.sh"
fi

# Dock 구성
if command -v dockutil &>/dev/null; then
  echo "Configuring Dock..."
  dockutil --remove all --no-restart

  dockutil --add /System/Applications/Apps.app --no-restart
  dockutil --add /System/Applications/System\ Settings.app --no-restart
  dockutil --add /Applications/Microsoft\ Outlook.app --no-restart
  dockutil --add /Applications/Microsoft\ Teams.app --no-restart
  dockutil --add /Applications/Google\ Chrome.app --no-restart
  dockutil --add /Applications/Zen.app --no-restart
  dockutil --add /Applications/WezTerm.app --no-restart
  dockutil --add /Applications/DataGrip.app --no-restart
  dockutil --add /Applications/Notion.app --no-restart
  dockutil --add /Applications/Slack.app --no-restart
  dockutil --add /Applications/Obsidian.app --no-restart
  dockutil --add /System/Applications/Notes.app --no-restart
  dockutil --add /System/Applications/Utilities/Activity\ Monitor.app --no-restart
  dockutil --add /Applications/ChatGPT.app --no-restart
  dockutil --add ~/Downloads --section others --view fan --display folder

  killall Dock 2>/dev/null
fi
