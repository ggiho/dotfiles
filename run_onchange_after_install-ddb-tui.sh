#!/bin/bash
# ddb-tui (DynamoDB TUI, github.com/ggiho/ddb-tui) 를 릴리스 바이너리로 ~/.local/bin 에 설치하고
# `ddb` 로도 부를 수 있게 링크한다. Rust 없이 받아서 쓰려고 cargo 빌드 대신 릴리스를 받는다.
#
# 버전을 올리려면 DDB_TUI_VERSION 만 바꾼다. run_onchange 라서 내용이 바뀌면 다음
# chezmoi apply/update 때 모든 Mac 에서 다시 돈다.
#
# cargo install 로 직접 설치한 머신(~/.cargo/bin/ddb-tui 가 있는 개발 머신)은 건드리지 않는다.
# ~/.local/bin 이 PATH 에서 먼저라, 여기에 깔면 직접 빌드한 쪽이 가려진다.
#
# 실패해도 apply 는 계속 간다. 수동 재실행: bash "$(chezmoi source-path)/run_onchange_after_install-ddb-tui.sh"
set -euo pipefail

DDB_TUI_VERSION=v0.3.2
BIN="$HOME/.local/bin"

if [ -x "${CARGO_HOME:-$HOME/.cargo}/bin/ddb-tui" ]; then
  echo "ddb-tui: cargo 로 설치된 머신이라 건너뜀 (cargo install --path . 로 갱신)"
  exit 0
fi

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) target=aarch64-apple-darwin ;;
  Darwin-x86_64) target=x86_64-apple-darwin ;;
  *)
    echo "  [WARN] ddb-tui: $(uname -s)-$(uname -m) 용 릴리스가 없어 건너뜀"
    exit 0
    ;;
esac

name="ddb-tui-$DDB_TUI_VERSION-$target"
url="https://github.com/ggiho/ddb-tui/releases/download/$DDB_TUI_VERSION/$name.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Installing ddb-tui $DDB_TUI_VERSION..."
if ! (cd "$tmp" &&
  curl -fsSLO "$url" &&
  curl -fsSLO "$url.sha256" &&
  shasum -a 256 -c "$name.tar.gz.sha256" >/dev/null &&
  tar xzf "$name.tar.gz"); then
  echo "  [WARN] ddb-tui 다운로드 또는 체크섬 확인 실패 -- 건너뜀 ($url)"
  exit 0
fi

mkdir -p "$BIN"
install -m 755 "$tmp/$name/ddb-tui" "$BIN/ddb-tui"
ln -sf ddb-tui "$BIN/ddb"
echo "ddb-tui: $BIN/ddb-tui ($BIN/ddb 로도 실행)"
