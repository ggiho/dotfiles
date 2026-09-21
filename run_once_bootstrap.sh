#!/bin/bash
set -e

# Brewfile로 패키지 설치
if [ -f "$HOME/.config/brew/Brewfile" ]; then
  echo "Installing packages from Brewfile..."
  # set -e 라서 가드가 없으면 패키지 하나가 실패할 때 스크립트가 여기서 죽고
  # TPM·kanata·Dock 설정이 전부 건너뛰어진다. 실패는 경고로 남기고 계속 간다.
  brew bundle install --file="$HOME/.config/brew/Brewfile" ||
    echo "  [WARN] Brewfile 설치 일부 실패 -- 위 로그에서 실패한 패키지를 확인하세요"
fi

# pgcli / mycli: PyPI 본이 아니라 로컬 포크의 editable 설치다.
#   pgcli  feature/atuin-history                   (atuin 백엔드 히스토리 + Up-arrow 피커)
#   mycli  feature/table-aliases-and-paste-hygiene (\t·\d·\dn·\list 별칭, paste hygiene)
# justfile 의 PGQ_PYTHON 이 pgcli 툴 venv 의 인터프리터를 직접 가리키므로
# (psql 이 없어 psycopg 를 쓴다) redshift-* 레시피가 이 설치에 의존한다.
#
# --with 로 얹는 것들:
#   mycli[all]              \llm / \ai 와 dataframe 변환. 빼면 조용히 사라진다.
#   psycopg, psycopg-binary justfile 의 redshift-* 레시피가 이 인터프리터를 쓴다.
#   catppuccin[pygments]    myclirc/pgcli config 의 syntax_style = catppuccin-mocha
#                           가 실제로 동작하려면 필요하다. 없으면 pygments 가 이름을
#                           못 찾고 경고 없이 native 로 폴백해서, 테마가 반쯤만
#                           적용된 상태가 된다.
#
# 두 repo 는 public 이라 인증 없이 clone 된다. 그래도 실패하면(네트워크 등)
# 경고만 남기고 부트스트랩은 계속 진행한다 -- PyPI 본을 대신 깔지는 않는다.
# 그러면 패치가 없는 채로 조용히 동작해서 더 헷갈린다.
# 체크아웃은 주제별로 분류하지 않고 origin 을 그대로 미러링한다
# ($SRC_ROOT/<호스트>/<org>/<repo>). 분류 판단이 없으니 같은 이름의 포크와
# 업스트림(ggiho/pgcli vs dbcli/pgcli)이 충돌 없이 공존하고, 회사별 경로가
# 공용 설정에 들어갈 일도 없다. SRC_ROOT 는 DOTFILES_SRC_ROOT 로 덮어쓸 수 있다.
SRC_ROOT="${DOTFILES_SRC_ROOT:-$HOME/src}"
if command -v uv &>/dev/null; then
  # 4번째 인자부터는 uv tool install 로 그대로 넘어간다 (--with 등).
  install_editable_tool() {
    local tool=$1 repo=$2 branch=$3
    shift 3
    # https://github.com/ggiho/pgcli.git  와  git@github.com:ggiho/pgcli.git
    # 둘 다 github.com/ggiho/pgcli 로 정규화한다.
    local slug=${repo#*://} dir
    slug=${slug#*@}     # scp 형식의 user@ 와 https 의 자격증명 제거
    slug=${slug/://}    # 첫 ':' 를 '/' 로 (github.com:ggiho -> github.com/ggiho)
    slug=${slug%.git}
    dir="$SRC_ROOT/$slug"
    if [ ! -d "$dir" ]; then
      echo "Cloning $tool ($branch)..."
      mkdir -p "$(dirname "$dir")"
      if ! git clone --branch "$branch" "$repo" "$dir"; then
        echo "  [WARN] $tool clone 실패 -- 네트워크나 repo 상태를 확인하세요."
        echo "         건너뜀. 수동: git clone -b $branch $repo $dir"
        echo "               그 뒤: uv tool install --editable $dir $*"
        return 0
      fi
    fi
    echo "Installing $tool (editable from $dir)..."
    uv tool install --editable "$dir" --force "$@" ||
      echo "  [WARN] $tool editable 설치 실패 -- 수동으로 확인하세요"
  }

  install_editable_tool pgcli https://github.com/ggiho/pgcli.git feature/atuin-history \
    --with "psycopg<3.3" --with "psycopg-binary<3.3" --with "catppuccin[pygments]"
  install_editable_tool mycli https://github.com/ggiho/mycli.git feature/table-aliases-and-paste-hygiene \
    --with "mycli[all]" --with "catppuccin[pygments]"
fi

# TPM (Tmux Plugin Manager)
if [ ! -d "$HOME/.config/tmux/.tmux/plugins/tpm" ]; then
  echo "Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/.tmux/plugins/tpm
fi

_tpm_install=~/.config/tmux/.tmux/plugins/tpm/bin/install_plugins
if [ -x "$_tpm_install" ]; then
  echo "Installing tmux plugins..."
  "$_tpm_install" || echo "  [WARN] tmux 플러그인 설치 실패 -- 건너뜀"
else
  echo "  [WARN] TPM 이 없어 tmux 플러그인 설치를 건너뜀"
fi
unset _tpm_install

# kanata (keyboard remapper) 설정
if command -v kanata &>/dev/null && [ -f "$HOME/.config/kanata/scripts/install-launchd.sh" ]; then
  echo "Installing Kanata VirtualHIDDevice and launchd services..."
  sudo "$HOME/.config/kanata/scripts/install-launchd.sh"
fi

# Dock 구성
# `dockutil --remove all` 은 기존 Dock 배치를 되돌릴 수 없게 지운다. 예전에는
# dockutil 이 work-only Brewfile 에만 있어서 다른 머신에서 우연히 건너뛰어졌는데,
# Brewfile 게이팅을 없앤 뒤로는 어디서나 설치된다. 그래서 명시적 opt-in 으로 바꾼다.
#   원할 때: DOTFILES_SETUP_DOCK=1 chezmoi apply
if [ "${DOTFILES_SETUP_DOCK:-0}" = "1" ] && command -v dockutil &>/dev/null; then
  echo "Configuring Dock..."
  dockutil --remove all --no-restart

  # 설치된 앱만 넣는다. 없는 경로를 --add 하면 Dock 에 물음표 아이콘이 남고,
  # 이 목록은 머신마다 설치 구성이 다른데도 모든 머신이 공유한다.
  # 나열 순서가 Dock 순서가 된다.
  for app in \
    "/System/Applications/Apps.app" \
    "/System/Applications/System Settings.app" \
    "/Applications/Google Chrome.app" \
    "/Applications/Slack.app" \
    "/Applications/WezTerm.app" \
    "/Applications/DataGrip.app" \
    "/Applications/Obsidian.app" \
    "/System/Applications/Notes.app" \
    "/System/Applications/Utilities/Activity Monitor.app" \
    "/Applications/NoSQL Workbench.app"
  do
    [ -d "$app" ] && dockutil --add "$app" --no-restart
  done

  dockutil --add ~/Downloads --section others --view fan --display folder

  killall Dock 2>/dev/null || true
fi
