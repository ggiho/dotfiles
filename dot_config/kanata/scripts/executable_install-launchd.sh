#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
PLIST_DIR=/Library/LaunchDaemons
VHID_LABEL=system/local.kanata.vhid
KANATA_LABEL=system/local.kanata
MANAGER='/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager'
VHID_DAEMON='/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon'
KANATA='/opt/homebrew/bin/kanata'

# Kanata on macOS uses Karabiner's VirtualHIDDevice runtime only.
# Do not remove the hidden manager or DriverKit daemon when cleaning up Karabiner UI/config.
[[ -x "$MANAGER" ]] || { echo "Missing VirtualHID manager required by kanata: $MANAGER" >&2; exit 1; }
[[ -x "$VHID_DAEMON" ]] || { echo "Missing VirtualHID daemon required by kanata: $VHID_DAEMON" >&2; exit 1; }
[[ -x "$KANATA" ]] || { echo "Missing kanata: $KANATA" >&2; exit 1; }

install -d -m 755 "$PLIST_DIR"
install -m 644 "$ROOT_DIR/launchd/local.kanata.vhid.plist" "$PLIST_DIR/local.kanata.vhid.plist"
install -m 644 "$ROOT_DIR/launchd/local.kanata.plist" "$PLIST_DIR/local.kanata.plist"
xattr -c "$PLIST_DIR/local.kanata.vhid.plist" 2>/dev/null || true
xattr -c "$PLIST_DIR/local.kanata.plist" 2>/dev/null || true

"$MANAGER" activate

launchctl bootout "$KANATA_LABEL" 2>/dev/null || true
launchctl bootout "$VHID_LABEL" 2>/dev/null || true

launchctl enable "$VHID_LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DIR/local.kanata.vhid.plist"
launchctl kickstart -k "$VHID_LABEL"
sleep 1
launchctl enable "$KANATA_LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DIR/local.kanata.plist"
launchctl kickstart -k "$KANATA_LABEL"
sleep 1

echo '--- local.kanata.vhid ---'
launchctl print "$VHID_LABEL" | sed -n '1,80p' || true
echo '--- local.kanata ---'
launchctl print "$KANATA_LABEL" | sed -n '1,120p' || true
echo '--- /tmp/kanata.err.log ---'
sed -n '1,120p' /tmp/kanata.err.log 2>/dev/null || true
echo '--- /tmp/kanata.out.log ---'
sed -n '1,120p' /tmp/kanata.out.log 2>/dev/null || true
