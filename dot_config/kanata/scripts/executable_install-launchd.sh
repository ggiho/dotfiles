#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
PLIST_DIR=/Library/LaunchDaemons
VHID_LABEL=system/local.kanata.vhid
KANATA_LABEL=system/local.kanata
GUARD_LABEL=system/local.kanata.guard
KARABINER_GRABBER=system/org.pqrs.service.daemon.Karabiner-Core-Service
KARABINER_VHID=system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon
MANAGER='/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager'
VHID_DAEMON='/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon'
KANATA='/opt/homebrew/bin/kanata'

if [[ ! -x "$MANAGER" || ! -x "$VHID_DAEMON" ]]; then
  "$SCRIPT_DIR/install-virtualhiddevice.sh"
fi

[[ -x "$MANAGER" ]] || { echo "Missing VirtualHID manager required by kanata: $MANAGER" >&2; exit 1; }
[[ -x "$VHID_DAEMON" ]] || { echo "Missing VirtualHID daemon required by kanata: $VHID_DAEMON" >&2; exit 1; }
[[ -x "$KANATA" ]] || { echo "Missing kanata: $KANATA" >&2; exit 1; }

install -d -m 755 "$PLIST_DIR"
install -m 644 "$ROOT_DIR/launchd/local.kanata.vhid.plist"  "$PLIST_DIR/local.kanata.vhid.plist"
install -m 644 "$ROOT_DIR/launchd/local.kanata.plist"       "$PLIST_DIR/local.kanata.plist"
install -m 644 "$ROOT_DIR/launchd/local.kanata.guard.plist" "$PLIST_DIR/local.kanata.guard.plist"
xattr -c "$PLIST_DIR/local.kanata.vhid.plist"  2>/dev/null || true
xattr -c "$PLIST_DIR/local.kanata.plist"       2>/dev/null || true
xattr -c "$PLIST_DIR/local.kanata.guard.plist" 2>/dev/null || true

"$MANAGER" activate

# ── 회사 MDM이 강제하는 Karabiner-Elements 대응 (Option A) ────────────────────
# kanata는 "우리쪽 local.kanata.vhid 데몬"으로 출력한다(원래 잘 되던 구성).
# 회사 Karabiner-Elements는 자체 grabber(키보드 선점)와 자체 VHID 데몬을 올려
# 두 데몬이 충돌(flapping)하거나 kanata가 device를 못 잡게 만든다.
# 따라서 grabber와 "회사 VHID 데몬" 둘 다 죽이고, 우리 local.kanata.vhid만 남긴다.
# 회사가 다시 깔면 local.kanata.guard가 자동으로 이 억제를 재적용한다.

KB_USER="${SUDO_USER:-$(stat -f '%Su' /dev/console)}"
KB_UID=$(id -u "$KB_USER")

# (a) grabber (Core-Service) — 시스템 + 사용자 도메인
launchctl bootout "$KARABINER_GRABBER" 2>/dev/null || true
launchctl disable "$KARABINER_GRABBER" 2>/dev/null || true
for svc in \
  org.pqrs.service.agent.karabiner_console_user_server \
  org.pqrs.service.agent.Karabiner-Core-Service-rev2 \
  org.pqrs.service.agent.Karabiner-Core-Service; do
  launchctl disable "gui/$KB_UID/$svc" 2>/dev/null || true
  launchctl bootout  "gui/$KB_UID/$svc" 2>/dev/null || true
done
pkill -f 'Karabiner-Elements/Karabiner-Core-Service' 2>/dev/null || true
pkill -f 'bin/karabiner_console_user_server'         2>/dev/null || true

# (b) 회사 VHID 데몬 제거 (우리 local.kanata.vhid만 쓰기 위해)
launchctl bootout "$KARABINER_VHID" 2>/dev/null || true
launchctl disable "$KARABINER_VHID" 2>/dev/null || true

# (c) 남은 VHID 데몬 프로세스 전부 정리 후, 우리 것만 새로 올린다
pkill -f 'Karabiner-VirtualHIDDevice-Daemon' 2>/dev/null || true
sleep 1

# ── 우리 VHID 데몬 (단독) ────────────────────────────────────────────────────
launchctl bootout "$VHID_LABEL" 2>/dev/null || true
launchctl enable "$VHID_LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DIR/local.kanata.vhid.plist"
launchctl kickstart -k "$VHID_LABEL"
sleep 2

# ── kanata 본체 ──────────────────────────────────────────────────────────────
launchctl bootout "$KANATA_LABEL" 2>/dev/null || true
launchctl enable "$KANATA_LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DIR/local.kanata.plist"
launchctl kickstart -k "$KANATA_LABEL"

# ── guard 데몬 (Karabiner 재부활 자동 감시/복구) ─────────────────────────────
launchctl bootout "$GUARD_LABEL" 2>/dev/null || true
launchctl enable "$GUARD_LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DIR/local.kanata.guard.plist"

sleep 4
echo '--- local.kanata state ---'
launchctl print "$KANATA_LABEL" 2>/dev/null | grep -E 'state|pid|program ' | head -6 || true
echo '--- driver 연결 상태 (out.log) ---'
grep -E 'driver connected|driver version matched|entering the event loop|connect_failed|Waiting for DriverKit' /tmp/kanata.out.log | tail -6 || true
echo '--- rootonly 소켓 상태 ---'
ls -la '/Library/Application Support/org.pqrs/tmp/rootonly/' 2>&1 || true
echo '--- VHID 데몬 프로세스 ---'
pgrep -fl 'Karabiner-VirtualHIDDevice-Daemon' || echo '  데몬 없음'
