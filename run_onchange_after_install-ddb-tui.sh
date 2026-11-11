#!/bin/bash
# Install the ddb-tui + sql-viewer release bundle without requiring Rust.
# Bump DDB_TUI_VERSION to update every Mac on the next chezmoi apply/update.
# Preserve cargo-installed ddb-tui, while still installing the SQL pager.
# Retry a failed download manually:
# bash "$(chezmoi source-path)/run_onchange_after_install-ddb-tui.sh"
set -euo pipefail

DDB_TUI_VERSION=v0.3.6
BIN="$HOME/.local/bin"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) target=aarch64-apple-darwin ;;
  Darwin-x86_64) target=x86_64-apple-darwin ;;
  *)
    echo "  [WARN] ddb-tui/sql-viewer: unsupported platform, skipping"
    exit 0
    ;;
esac

name="ddb-tui-$DDB_TUI_VERSION-$target"
url="https://github.com/ggiho/ddb-tui/releases/download/$DDB_TUI_VERSION/$name.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; rm -f "$BIN/.ddb-tui.$$" "$BIN/.sql-viewer.$$"' EXIT

echo "Installing ddb-tui + sql-viewer $DDB_TUI_VERSION..."
if ! (cd "$tmp" &&
  curl --connect-timeout 15 --max-time 180 --retry 2 -fsSLO "$url" &&
  curl --connect-timeout 15 --max-time 60 --retry 2 -fsSLO "$url.sha256" &&
  shasum -a 256 -c "$name.tar.gz.sha256" >/dev/null &&
  tar xzf "$name.tar.gz" &&
  test -x "$name/ddb-tui" && test -x "$name/sql-viewer"); then
  echo "  [WARN] ddb-tui/sql-viewer: download, checksum or package check failed; keeping existing binaries ($url)"
  exit 0
fi

mkdir -p "$BIN"
if [ -x "${CARGO_HOME:-$HOME/.cargo}/bin/ddb-tui" ]; then
  echo "ddb-tui: keeping cargo-installed binary"
else
  install -m 755 "$tmp/$name/ddb-tui" "$BIN/.ddb-tui.$$"
  mv -f "$BIN/.ddb-tui.$$" "$BIN/ddb-tui"
  ln -sf ddb-tui "$BIN/ddb"
  echo "ddb-tui: $BIN/ddb-tui (also available as ddb)"
fi
install -m 755 "$tmp/$name/sql-viewer" "$BIN/.sql-viewer.$$"
mv -f "$BIN/.sql-viewer.$$" "$BIN/sql-viewer"
echo "sql-viewer: $BIN/sql-viewer"
