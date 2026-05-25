#!/bin/zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO='pqrs-org/Karabiner-DriverKit-VirtualHIDDevice'
MANAGER='/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager'
VHID_DAEMON='/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon'

is_installed() {
  [[ -x "$MANAGER" && -x "$VHID_DAEMON" ]]
}

if is_installed; then
  echo 'Karabiner DriverKit VirtualHIDDevice already installed.'
  exit 0
fi

if [[ "${1:-}" == '--check' ]]; then
  echo 'Karabiner DriverKit VirtualHIDDevice is not installed.' >&2
  exit 1
fi

if [[ "$(uname -s)" != 'Darwin' ]]; then
  echo 'Karabiner DriverKit VirtualHIDDevice is only needed on macOS.' >&2
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

tmp_dir=$(mktemp -d -t kanata-vhid.XXXXXX)
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

pkg=''

if command -v gh >/dev/null 2>&1; then
  if gh release download --repo "$REPO" --pattern 'Karabiner-DriverKit-VirtualHIDDevice-*.pkg' --dir "$tmp_dir" >/dev/null 2>&1; then
    pkgs=("$tmp_dir"/Karabiner-DriverKit-VirtualHIDDevice-*.pkg(N))
    if (( ${#pkgs[@]} > 0 )); then
      pkg="${pkgs[1]}"
    fi
  fi
fi

if [[ -z "$pkg" ]]; then
  api_url="https://api.github.com/repos/${REPO}/releases/latest"
  asset_url=$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api_url" \
    | sed -nE 's/.*"browser_download_url": "([^"]*Karabiner-DriverKit-VirtualHIDDevice-[^"]*\.pkg)".*/\1/p' \
    | head -n 1)

  if [[ -z "$asset_url" ]]; then
    echo "Could not find latest Karabiner DriverKit VirtualHIDDevice pkg from $api_url" >&2
    exit 1
  fi

  pkg="$tmp_dir/$(basename "$asset_url")"
  curl -fL "$asset_url" -o "$pkg"
fi

echo "Installing $pkg"
installer -pkg "$pkg" -target /

if ! is_installed; then
  echo 'VirtualHIDDevice install finished, but required binaries were not found.' >&2
  echo "Missing one of:" >&2
  echo "  $MANAGER" >&2
  echo "  $VHID_DAEMON" >&2
  exit 1
fi

echo 'Karabiner DriverKit VirtualHIDDevice installed.'
echo 'If macOS asks for system extension approval, allow org.pqrs.Karabiner-DriverKit-VirtualHIDDevice in Privacy & Security, then rerun the Kanata launchd installer.'
