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

사용자가 선택한 **Ctrl+T**로 쿼리 입력창과 마지막 결과창을 왕복합니다. 입력 중인
쿼리·커서와 결과의 선택·검색·정렬·스크롤을 보존하며 SQL을 재실행하지 않습니다.
쿼리 입력창의 기존 글자 순서 바꾸기를 대체합니다. Alt+E·Alt+T와 전역 터미널 키는
변경하지 않습니다. 기존 CLI는 재시작하고 새 결과를 조회한 뒤 사용할 수 있습니다.
결과창 검색은 `f` 또는 `/`로 시작하고, `n` / `N`으로 다음·이전 항목을 찾습니다.

단순 SELECT는 최대 500행씩 추가 조회합니다. 상태줄에 읽은 행 수와 추가 조회 가능 여부,
검색어·일치 개수·정렬 방향이 유지됩니다.
한 컬럼 목록은 최대 3열로 배치하고 항목 사이에 테마에 맞는 구분선을 표시합니다.
화면이 좁으면 열 수를 줄이며 이름과 기존 위→아래 순서를 유지합니다. 검색·정렬은 현재 읽은 행에 적용되며,
실제 NULL은 숫자 정렬을 방해하지 않고 항상 뒤에 놓입니다.
트랜잭션·복잡한 쿼리는 기존 전체 수신 방식을 유지합니다. 이전 동작은
`SQL_VIEWER_PAGING=0 mycli` 또는 `SQL_VIEWER_PAGING=0 pgcli`로 사용할 수 있습니다.

릴리스의 최적화 바이너리를 설치하므로 긴 값에서도 빠르게 표시됩니다. 직접 소스에서
갱신할 때도 `cargo build --release --locked --bin sql-viewer` 결과를 사용하세요.
화면 폭을 넘은 줄의 너비 검사는 조기에 끝내 불필요한 전체 문자열 순회를 피합니다.

설치·업데이트 시 Python 바이트코드를 미리 생성하고 `--version`으로 모듈을 한 번
초기화합니다. DB에 연결하지 않으며, 업데이트 직후 첫 실행의 초기화 부담을 줄입니다.
재부팅 후 OS 캐시나 실제 네트워크·인증 지연까지 제거하는 것은 아닙니다.

기존 Mac의 editable mycli·pgcli 포크도 별도 onchange 스크립트로 갱신됩니다. 다른 브랜치,
추적 중인 로컬 수정, 분기된 이력이 있으면 덮어쓰지 않고 경고합니다. 버전을 올릴 때는
스크립트의 revision 두 개도 갱신합니다.

설치 위치는 `~/.local/bin/sql-viewer`입니다. 릴리스 체크섬을 검증한 뒤 설치하며,
cargo로 설치한 ddb-tui가 있어도 SQL 뷰어는 설치합니다. 실패하면 기존 바이너리를 유지하고
pager는 less로 표시합니다. 초기 부트스트랩 없이 `chezmoi init --apply ggiho`를 직접 쓰는 경우
Homebrew가 먼저 설치되어 있어야 합니다.

버전을 갱신할 때는 `run_onchange_after_install-ddb-tui.sh`의 `DDB_TUI_VERSION`을 올립니다.

### mycli 즐겨찾기

- `\f`: 이름·SQL 검색과 미리보기. 선택하면 쿼리 입력창으로 불러옵니다.
- `\fe` 또는 `\fe 이름`: 즐겨찾기 편집. Save / Save as / Cancel을 지원합니다.
- `\f 이름`: 기존처럼 바로 실행합니다. `\fs`·`\fd`도 기존대로 사용할 수 있습니다.

템플릿 변수 `$1`·`{{ kv.name }}`는 원문으로 불러옵니다. 입력창에서 값을 채운 뒤
실행하거나, 기존 `\f 이름 인자` 방식으로 치환합니다. 저장은 기존 설정 파일에
반영되며, chezmoi 동기화는 기존 관리 흐름을 따릅니다. 업데이트 후 새 mycli에서 사용합니다.

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
