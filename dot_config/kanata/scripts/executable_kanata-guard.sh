#!/bin/zsh
# kanata-guard
# ─────────────────────────────────────────────────────────────────────────────
# 회사 MDM이 Karabiner-Elements를 주기적으로 재설치/업데이트하면, grabber
# (org.pqrs.service.daemon.Karabiner-Core-Service, 시스템 데몬)가 되살아나
# 물리 키보드를 선점(exclusive grab)하고 자체 VHID 데몬까지 다시 올려서
# kanata가 device를 못 잡거나 가상 키보드 등록이 실패한다.
#
# 이 스크립트는 root LaunchDaemon(local.kanata.guard)에서 WatchPaths + StartInterval로
# 주기 실행되며, grabber가 감지될 때만 그것을 죽이고 kanata를 재연결한다.
# grabber가 없으면 즉시 종료하므로 평상시엔 아무 것도 건드리지 않는다(idempotent).
#
# 출력(가상 키보드)은 회사 Karabiner의 VHID 데몬을 그대로 재사용한다
# (항상 존재하므로 가장 안정적). 따라서 우리쪽 local.kanata.vhid는 쓰지 않는다.
set -uo pipefail

GRABBER_DAEMON=org.pqrs.service.daemon.Karabiner-Core-Service
CONSOLE_USER=$(stat -f '%Su' /dev/console 2>/dev/null)
CUID=$(id -u "$CONSOLE_USER" 2>/dev/null || echo "")

grabber_alive() { pgrep -f 'Karabiner-Elements/Karabiner-Core-Service' >/dev/null 2>&1; }

# grabber가 없으면 정상 상태 → 아무 것도 안 함
grabber_alive || exit 0

logger -t kanata-guard "Karabiner grabber detected — suppressing and reconnecting kanata"

# 1) 시스템 도메인 grabber 데몬 정지 + 비활성화
launchctl bootout "system/$GRABBER_DAEMON" 2>/dev/null || true
launchctl disable "system/$GRABBER_DAEMON" 2>/dev/null || true

# 2) 사용자 도메인 grabber 에이전트 정지 + 비활성화
if [[ -n "$CUID" ]]; then
  for svc in \
    org.pqrs.service.agent.karabiner_console_user_server \
    org.pqrs.service.agent.Karabiner-Core-Service-rev2 \
    org.pqrs.service.agent.Karabiner-Core-Service; do
    launchctl bootout "gui/$CUID/$svc" 2>/dev/null || true
    launchctl disable "gui/$CUID/$svc" 2>/dev/null || true
  done
fi

# 3) 잔존 grabber 프로세스 강제 종료
pkill -f 'Karabiner-Elements/Karabiner-Core-Service' 2>/dev/null || true
pkill -f 'bin/karabiner_console_user_server' 2>/dev/null || true

# 4) 우리쪽 중복 VHID 데몬이 혹시 떠 있으면 정지 (회사 VHID 데몬만 사용)
launchctl bootout system/local.kanata.vhid 2>/dev/null || true

# 5) 회사 VHID 데몬을 재시작해 rootonly 소켓을 재생성 (grabber 충돌로 stale 됐을 수 있음)
launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || true
sleep 2

# 6) kanata 재연결 (회사 VHID 데몬에 다시 붙도록)
launchctl kickstart -k system/local.kanata 2>/dev/null || true
logger -t kanata-guard "suppression complete"
