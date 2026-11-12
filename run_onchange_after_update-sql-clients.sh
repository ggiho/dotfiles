#!/bin/bash
# Refresh the editable CLI forks when their pinned integration revisions change.
# Preserve tracked local edits, other branches and divergent history.
set -euo pipefail

SRC_ROOT="${DOTFILES_SRC_ROOT:-$HOME/src}"
MYCLI_REVISION=830b920bee55b6ca1a39d37cd2085a82dd5c2dea
PGCLI_REVISION=ddb030eb426a342778ae400f31c623fa9cd6ffa5

if ! command -v uv >/dev/null 2>&1; then
  echo '[WARN] SQL clients: uv is missing; rerun this script after installing Brewfile packages.'
  exit 0
fi

update_client() {
  local tool=$1 branch=$2 revision=$3
  shift 3
  local repo="https://github.com/ggiho/$tool.git"
  local dir="$SRC_ROOT/github.com/ggiho/$tool"
  if [ ! -d "$dir" ]; then
    mkdir -p "$(dirname "$dir")"
    if ! git clone --branch "$branch" "$repo" "$dir"; then
      echo "[WARN] $tool: clone failed; keeping existing installation"
      return 0
    fi
  fi
  if [ "$(git -C "$dir" branch --show-current)" != "$branch" ] ||
     ! git -C "$dir" diff --quiet || ! git -C "$dir" diff --cached --quiet; then
    echo "[WARN] $tool: different branch or local edits; update manually in $dir"
    return 0
  fi
  if ! git -C "$dir" fetch --quiet "$repo" "$branch"; then
    echo "[WARN] $tool: fetch failed; keeping existing installation"
    return 0
  fi
  if ! git -C "$dir" merge-base --is-ancestor "$revision" HEAD; then
    if ! git -C "$dir" merge-base --is-ancestor HEAD "$revision"; then
      echo "[WARN] $tool: divergent history; update manually in $dir"
      return 0
    fi
    git -C "$dir" merge --ff-only "$revision" || return 0
  fi
  if uv tool install --editable "$dir" --force --compile-bytecode "$@"; then
    # Load Python/native modules during setup, without opening a DB connection.
    "$tool" --version >/dev/null 2>&1 ||
      echo "[WARN] $tool: startup warmup failed; check the installation manually"
  else
    echo "[WARN] $tool: editable installation failed; retry manually"
  fi
}

update_client pgcli feature/atuin-history "$PGCLI_REVISION" \
  --with 'psycopg>=3.3.5' --with 'psycopg-binary>=3.3.5' --with 'catppuccin[pygments]'
update_client mycli feature/table-aliases-and-paste-hygiene "$MYCLI_REVISION" \
  --with 'mycli[all]' --with 'catppuccin[pygments]'
