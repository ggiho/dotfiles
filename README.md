# dotfiles

## 새 Mac 세팅

### 1. dotfiles 설치

```bash
curl -fsSL https://raw.githubusercontent.com/ggiho/dotfiles/main/install.sh | bash
```

자동으로 아래 순서로 실행됩니다:

1. Homebrew 설치
2. chezmoi 설치
3. dotfiles 적용 (`chezmoi init --apply`)
4. Brewfile로 패키지 설치
5. ddb-tui와 SQL 결과 뷰어 설치 (Apple Silicon/Intel 자동 선택, Rust 불필요)
6. macOS 기본 설정 적용

자동화되지 않는 항목(macOS 권한, 비밀 파일, 앱 내부 설치)은 [docs/manual-setup.md](docs/manual-setup.md) 참고.

---

## 관리

### 변경사항 반영

```bash
# 파일 수정 후 chezmoi에 반영
chezmoi add <파일경로>

# chezmoi source로 이동
cd ~/.local/share/chezmoi
git add .
git commit -m "message"
git push
```

### 다른 Mac에서 업데이트

```bash
chezmoi update
```

### SQL 결과 뷰어 설치/복구

새 Mac은 위 초기 설치 명령으로 mycli·pgcli 포크, pager 설정과 `sql-viewer`까지 함께 설치됩니다.
이미 chezmoi를 쓰는 Mac에서는 `chezmoi update`를 실행하면 됩니다.

다운로드 실패 시 수동 재시도:

```bash
bash "$(chezmoi source-path)/run_onchange_after_install-ddb-tui.sh"
```

결과 전환용 단축키는 지정하지 않습니다. 사용할 키를 사용자에게 확인한 뒤에만
CLI·뷰어·터미널 바인딩을 추가합니다. 결과창에서 기존 `q` / Escape로 입력창에 돌아갈 수
있으며 세션별 결과 캐시와 화면 상태 저장 기능은 유지됩니다.

기존 Mac의 editable mycli·pgcli 포크도 별도 onchange 스크립트로 갱신됩니다. 다른 브랜치,
추적 중인 로컬 수정, 분기된 이력이 있으면 덮어쓰지 않고 경고합니다. 버전을 올릴 때는
스크립트의 revision 두 개도 갱신합니다.

설치 위치는 `~/.local/bin/sql-viewer`입니다. 릴리스 체크섬을 검증한 뒤 설치하며,
cargo로 설치한 ddb-tui가 있어도 SQL 뷰어는 설치합니다. 실패하면 기존 바이너리를 유지하고
pager는 less로 표시합니다. 초기 부트스트랩 없이 `chezmoi init --apply ggiho`를 직접 쓰는 경우
Homebrew가 먼저 설치되어 있어야 합니다.

버전을 갱신할 때는 `run_onchange_after_install-ddb-tui.sh`의 `DDB_TUI_VERSION`을 올립니다.

### Brewfile 업데이트

```bash
brew bundle dump --file=~/.config/brew/Brewfile --force
chezmoi add ~/.config/brew/Brewfile
```

---

## 구성

| 파일/폴더 | 설명 |
|-----------|------|
| `install.sh` | 새 Mac 초기 세팅 스크립트 |
| `run_once_bootstrap.sh` | Brewfile로 패키지 설치 (최초 1회) |
| `run_onchange_macos-defaults.sh` | macOS 시스템 설정 (변경 시 재실행) |
| `run_onchange_after_claude-notify-hooks.sh` | Claude Code 알림 hook을 settings.json에 병합 |
| `run_onchange_after_install-ddb-tui.sh` | ddb-tui·sql-viewer 릴리스 설치 + `ddb` 링크 (버전 바꾸면 재실행) |
| `run_onchange_after_update-sql-clients.sh` | SQL 결과 왕복 기능이 있는 mycli·pgcli 포크를 안전하게 갱신 |
| `dot_claude/hooks/` | Claude Code 알림 hook 스크립트 |
| `dot_zshrc` | zsh 설정 |
| `dot_config/wezterm/` | WezTerm 설정 |
| `dot_config/brew/Brewfile` | Homebrew 패키지 목록 |
