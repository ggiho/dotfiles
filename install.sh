#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-ggiho}"

load_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_bin" ]]; then
      eval "$("$brew_bin" shellenv)"
      return 0
    fi
  done

  return 1
}

if ! load_homebrew; then
  echo 'Installing Homebrew...'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_homebrew || {
    echo 'Homebrew was installed, but brew is still not on PATH.' >&2
    echo 'Open a new shell or add brew shellenv to your shell profile, then rerun this script.' >&2
    exit 1
  }
fi

if ! command -v chezmoi >/dev/null 2>&1; then
  echo 'Installing chezmoi...'
  brew install chezmoi
fi

source_dir="$(chezmoi source-path 2>/dev/null || true)"
if [[ -n "$source_dir" && -d "$source_dir/.git" ]]; then
  echo 'Updating existing chezmoi source and applying dotfiles...'
  chezmoi update --apply
else
  echo "Initializing chezmoi from $DOTFILES_REPO and applying dotfiles..."
  chezmoi init --apply "$DOTFILES_REPO"
fi

if command -v kanata >/dev/null 2>&1 && [[ -x "$HOME/.config/kanata/scripts/install-launchd.sh" ]]; then
  echo 'Ensuring Kanata launchd services are installed...'
  sudo "$HOME/.config/kanata/scripts/install-launchd.sh"
fi
