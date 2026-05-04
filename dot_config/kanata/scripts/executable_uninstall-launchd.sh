#!/bin/zsh
set -euo pipefail

launchctl bootout system/local.kanata 2>/dev/null || true
launchctl bootout system/local.kanata.vhid 2>/dev/null || true
rm -f /Library/LaunchDaemons/local.kanata.plist /Library/LaunchDaemons/local.kanata.vhid.plist
