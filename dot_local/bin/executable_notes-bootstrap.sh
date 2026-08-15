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
typeset -A pkgs=( nvim neovim  rg ripgrep  bat bat  fzf fzf )
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

echo "▶ 5. 남은 수동 단계"
cat <<'EOF'
  - 새 셸 열기 또는 `sz`  → 캡처 함수 n/nc/nf/ng 활성화
  - Obsidian 앱 실행 → "Open folder as vault" → ~/40_Notes 선택
EOF
echo "✅ 부트스트랩 완료"
