#!/bin/bash
set -e

# Brewfile로 패키지 설치
if [ -f "$HOME/.config/brew/Brewfile" ]; then
  echo "Installing packages from Brewfile..."
  brew bundle install --file="$HOME/.config/brew/Brewfile"
fi

# pgcli / mycli: PyPI 본이 아니라 로컬 포크의 editable 설치다.
#   pgcli  feature/atuin-history                   (atuin 백엔드 히스토리 + Up-arrow 피커)
#   mycli  feature/table-aliases-and-paste-hygiene (\t·\d·\dn·\list 별칭, paste hygiene)
# justfile 의 PGQ_PYTHON 이 pgcli 툴 venv 의 인터프리터를 직접 가리키므로
# (psql 이 없어 psycopg 를 쓴다) redshift-* 레시피가 이 설치에 의존한다.
#
# 두 브랜치는 아직 원격에 push 되지 않아 clone 할 수 없다. 체크아웃이 있으면
# 설치하고, 없으면 건너뛰되 무엇을 해야 하는지 알린다. push 된 뒤에는 아래
# else 절을 git clone 으로 바꾸면 된다.
PROJECTS="$HOME/20_Work/01_Asurion/projects"
if command -v uv &>/dev/null; then
  for tool in pgcli mycli; do
    if [ -d "$PROJECTS/$tool" ]; then
      echo "Installing $tool (editable from $PROJECTS/$tool)..."
      uv tool install --editable "$PROJECTS/$tool" --force || \
        echo "  [WARN] $tool editable 설치 실패 — 수동으로 확인하세요"
    else
      echo "  [SKIP] $PROJECTS/$tool 없음 — 커스텀 $tool 미설치."
      echo "         포크 체크아웃을 복원한 뒤: uv tool install --editable $PROJECTS/$tool"
      echo "         (PyPI 본을 깔면 포크 패치가 없다)"
    fi
  done
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
