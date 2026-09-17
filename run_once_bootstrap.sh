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
# 두 repo 는 private 이라 clone 에 인증이 필요하다. 실패하면 경고만 남기고
# 부트스트랩은 계속 진행한다 (PyPI 본을 대신 깔지는 않는다 -- 그러면 패치가
# 없는 채로 조용히 동작해서 더 헷갈린다).
PROJECTS="$HOME/20_Work/01_Asurion/projects"
if command -v uv &>/dev/null; then
  install_editable_tool() {
    local tool=$1 repo=$2 branch=$3 dir="$PROJECTS/$1"
    if [ ! -d "$dir" ]; then
      echo "Cloning $tool ($branch)..."
      mkdir -p "$PROJECTS"
      if ! git clone --branch "$branch" "$repo" "$dir"; then
        echo "  [WARN] $tool clone 실패 (private repo -- gh auth login 확인)."
        echo "         건너뜀. 수동: git clone -b $branch $repo $dir"
        echo "               그 뒤: uv tool install --editable $dir"
        return 0
      fi
    fi
    echo "Installing $tool (editable from $dir)..."
    uv tool install --editable "$dir" --force ||
      echo "  [WARN] $tool editable 설치 실패 -- 수동으로 확인하세요"
  }

  install_editable_tool pgcli https://github.com/ggiho/pgcli.git feature/atuin-history
  install_editable_tool mycli https://github.com/ggiho/mycli.git feature/table-aliases-and-paste-hygiene
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
