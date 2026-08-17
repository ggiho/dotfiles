#!/bin/zsh
# 새 Mac에서 nvim+Obsidian 노트 워크플로우를 세팅한다 (idempotent).
# 전제: 먼저 `chezmoi init/apply`로 dotfiles(aliases/nvim/plist)가 적용돼 있어야 함.
set -uo pipefail

VAULT="$HOME/40_Notes"
VAULT_REMOTE="https://github.com/ggiho/obsidian-vault.git"

echo "▶ 1. 의존성 확인/설치 (Homebrew)"
if ! command -v brew >/dev/null 2>&1; then
  echo "  ✗ Homebrew가 없습니다 — 먼저 설치: https://brew.sh"; exit 1
fi
typeset -A pkgs=( nvim neovim  rg ripgrep  bat bat  fzf fzf  jq jq  glow glow  node node )
for bin pkg in "${(@kv)pkgs}"; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo "  ✓ $bin"
  else
    echo "  설치: $pkg"; brew install "$pkg"
  fi
done

echo "▶ 2. 볼트 clone → $VAULT"
if [[ -d "$VAULT/.git" ]]; then
  echo "  ✓ 이미 존재"
else
  git clone "$VAULT_REMOTE" "$VAULT" && echo "  ✓ clone 완료"
fi

echo "▶ 3. 상태 디렉토리 생성"
mkdir -p "$HOME/.local/state" && echo "  ✓ ~/.local/state"

echo "▶ 4. launchd 자동백업 등록"
PLIST="$HOME/Library/LaunchAgents/com.giho.obsidian-vault-sync.plist"
if [[ -f "$PLIST" ]]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load -w "$PLIST" && echo "  ✓ 등록됨 (매시간 + 로그인 시)"
else
  echo "  ✗ plist 없음 — 'chezmoi apply' 먼저 실행하세요"
fi

echo "▶ 5. Obsidian 앱에 볼트 자동 등록"
OBS_JSON="$HOME/Library/Application Support/obsidian/obsidian.json"
obsidian_was_running=0
# obsidian.json은 Obsidian이 종료할 때 덮어쓰므로, 실행 중이면 먼저 종료해야 한다.
if pgrep -x Obsidian >/dev/null 2>&1; then
  obsidian_was_running=1
  echo "  Obsidian 실행 중 — 종료 후 등록"
  osascript -e 'tell application "Obsidian" to quit' >/dev/null 2>&1 || true
  for _ in {1..10}; do pgrep -x Obsidian >/dev/null 2>&1 || break; sleep 0.5; done
  if pgrep -x Obsidian >/dev/null 2>&1; then
    echo "  응답 없음 — 강제 종료"; killall Obsidian 2>/dev/null || true; sleep 1
  fi
fi
mkdir -p "${OBS_JSON:h}"
[[ -f "$OBS_JSON" ]] || echo '{"vaults":{}}' > "$OBS_JSON"
if jq -e --arg p "$VAULT" 'any(.vaults[]; .path==$p)' "$OBS_JSON" >/dev/null 2>&1; then
  echo "  ✓ 이미 등록됨"
else
  id=$(openssl rand -hex 8)
  ts=$(( $(date +%s) * 1000 ))
  jq --arg id "$id" --arg p "$VAULT" --argjson ts "$ts" \
    '.vaults[$id] = {path:$p, ts:$ts, open:true}' "$OBS_JSON" > "$OBS_JSON.tmp" \
    && mv "$OBS_JSON.tmp" "$OBS_JSON" && echo "  ✓ 등록 완료"
fi
# 우리가 종료시켰으면 다시 열어준다 (등록된 볼트로 자동 오픈).
if (( obsidian_was_running )); then
  echo "  Obsidian 재실행"; open -a Obsidian >/dev/null 2>&1 || true
fi

echo "▶ 6. 남은 단계 (딱 하나)"
echo "  - 새 셸 열기 또는 \`sz\`  → 캡처 함수 n/nc/nf/ng 활성화"
echo "✅ 부트스트랩 완료 — Obsidian 실행하면 플러그인·테마·설정 그대로 적용됩니다"
