#!/bin/zsh
# Obsidian 볼트 자동 백업: 변경이 있으면 커밋하고 best-effort로 push.
# launchd(com.giho.obsidian-vault-sync)가 매시간 + 로그인 시 실행.
# 볼트가 ~/40_Notes (TCC 보호 폴더 밖)라 별도 권한 없이 백그라운드 접근 가능.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"
cd "$HOME" 2>/dev/null || true          # launchd cwd 이슈 회피
VAULT="${NOTES_DIR:-$HOME/40_Notes}"

ts() { date '+%F %T'; }

# 볼트 접근 가능 여부 먼저 확인 (TCC 차단 시 명확히 로깅하고 종료)
if ! git -C "$VAULT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "$(ts) ERROR: 볼트 접근 불가 — Full Disk Access 미부여 또는 경로 문제"
  exit 1
fi

if [[ -n "$(git -C "$VAULT" status --porcelain 2>/dev/null)" ]]; then
  git -C "$VAULT" add -A
  git -C "$VAULT" commit -m "vault: auto-sync $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1
  echo "$(ts) committed"
else
  echo "$(ts) no changes"
fi

# 원격 변경을 먼저 통합 (다중 PC 충돌 방지). 충돌/오프라인이면 안전하게 중단하고 push 건너뜀.
if ! git -C "$VAULT" pull --rebase --autostash >/dev/null 2>&1; then
  git -C "$VAULT" rebase --abort >/dev/null 2>&1 || true
  echo "$(ts) pull 실패/충돌 — 수동 확인 필요, push 건너뜀 (로컬 커밋은 보존됨)"
  exit 1
fi

# push는 실패해도(오프라인 등) 스크립트를 죽이지 않음 — 로컬 커밋은 이미 안전
if git -C "$VAULT" push origin HEAD >/dev/null 2>&1; then
  echo "$(ts) pushed"
else
  echo "$(ts) push skipped/failed (로컬 커밋은 보존됨)"
fi
