# 수작업 항목 (chezmoi 가 대신 못 하는 것)

`chezmoi apply` 로 끝나지 않는 것들. 새 머신 세팅과, 이 머신에서 아직 안 돌린 것 둘 다.

- **A. 보류 중인 chezmoi 스크립트** — 이 머신에서 아직 실행되지 않음
- **B. repo 에 없는 파일** — 자격증명·내부정보라 직접 넣어야 함
- **C. 로그인·키체인** — 계정 인증
- **D. repo 로 재현 안 되는 설치** — 포크 체크아웃 등

관련: [DataGrip 플러그인 재설치 목록](datagrip-plugins.md)

---

## A. 보류 중인 chezmoi 스크립트

`chezmoi status` 의 `R` 은 "다음 apply 에서 실행될 스크립트"다. 아래 4개는 부작용이
있어서 자동으로 돌리지 않았다. `chezmoi state dump` 의 `scriptState` 에 기록이 없으면
미실행 상태다.

| 스크립트 | 하는 일 | 주의 |
|----------|---------|------|
| `run_once_bootstrap.sh` | `brew bundle install`, TPM 설치, kanata launchd, Dock 재구성, pgcli/mycli editable 설치 | **`sudo` 암호 입력** (kanata). `dockutil --remove all` 로 Dock 이 재배치된다. `brew bundle install` 은 구버전 패키지를 **업그레이드**한다 — 원치 않으면 `--no-upgrade` |
| `run_onchange_macos-defaults.sh` | `defaults write` 102줄 (키 반복, 트랙패드 등) | 시스템 설정을 바꾼다. 일부는 재로그인 후 적용 |
| `run_once_after_notes-bootstrap.sh` | 노트 워크플로우 부트스트랩 | **실행 중인 Obsidian 을 종료시킨다** (`obsidian.json` 을 Obsidian 이 종료 시 덮어쓰기 때문). 멱등적이라 재실행은 안전 |
| `run_onchange_after_claude-notify-hooks.sh` | `~/.claude/settings.json` 에 알림 hook 을 jq 로 병합 | 멱등적. `jq` 없으면 조용히 건너뜀 |

```sh
chezmoi apply                                     # 파일 + 스크립트 전부
chezmoi apply --exclude scripts                   # 파일만 (안전)
chezmoi apply --include scripts --exclude files    # 스크립트만
brew bundle install --no-upgrade --file ~/.config/brew/Brewfile   # 업그레이드 없이 빠진 것만
```

## B. repo 에 없는 파일 (직접 넣기)

`.chezmoiignore` 로 무조건 제외된 것들. 공개 repo 라서 자격증명·내부 호스트명은 넣지 않는다.

| 경로 | 없으면 | 복원 방법 |
|------|--------|-----------|
| `~/.config/mysql/hosts` | `db`, `dbq`, justfile 의 모든 DB 레시피가 서버 목록을 못 읽음 | 직접 작성. 형식: `표시명:host:port:user[:type[:db]]` |
| `~/.config/justfile/prod.just` | PROD 터널 레시피 없음 (justfile 은 `import?` 라 조용히 무시) | 직접 작성 (내부 호스트명 포함) |
| `~/.claude/settings.json` | Claude Code 게이트웨이 설정 없음 | 직접 작성. 알림 hook 부분만 A 의 스크립트가 병합해준다 |
| `~/.soluto_dm.env` | — | 직접 작성 |
| `~/.config/redshift/`, `~/.config/harlequin/`, `~/.config/mycli/` | 각 툴 접속 정보 없음 | 직접 작성 |
| `~/.config/gh/`, `~/.config/gcloud/`, `~/.config/configstore/`, `~/.config/opencode/` | 각 CLI 미인증 | 각 툴 로그인 (C 참고) |
| `~/.config/karabiner/`, Karabiner plist | Karabiner 설정 (Kanata 는 VirtualHIDDevice 런타임만 필요) | 필요 시 직접 |

히스토리 파일(`.zsh_history`, `.mysql_history`, `.mycli-history`, `.duckdb_history`,
`.viminfo`)과 로그도 제외 대상이지만 복원할 필요는 없다.

## C. 로그인·키체인

| 항목 | 명령 | 필요한 이유 |
|------|------|-------------|
| MySQL 비밀번호 | `security add-generic-password -s "mysql-db-connect" -a "<db-user>" -w` | `db`/`dbq`/justfile 이 키체인에서 읽는다. hosts 의 user 마다 하나씩 |
| GitHub | `gh auth login` | D 의 private repo clone 에 필요 |
| atuin | `atuin login` (동기화: `https://api.atuin.sh/`) | 셸 히스토리 동기화. 안 하면 로컬 전용으로 동작 |
| gcloud / azure | `gcloud auth login`, `az login` | 해당 CLI 사용 시 |

## D. repo 로 재현 안 되는 설치

### pgcli / mycli — 로컬 포크의 editable 설치

PyPI 본이 아니다. Brewfile 에 `uv "pgcli"` / `uv "mycli"` 를 적으면 업스트림이 깔려
패치가 사라지므로 **일부러 빼 뒀다**.

| 도구 | repo (private) | 브랜치 | 패치 내용 |
|------|----------------|--------|-----------|
| pgcli | `ggiho/pgcli` | `feature/atuin-history` | atuin 백엔드 쿼리 히스토리 + Up-arrow 피커 |
| mycli | `ggiho/mycli` | `feature/table-aliases-and-paste-hygiene` | `\t`·`\d`·`\dn`·`\list` psql 스타일 별칭, 붙여넣기/source/편집 SQL 의 invisible 문자 제거 |

`run_once_bootstrap.sh` 가 clone + `uv tool install --editable` 까지 해주지만,
**private repo 라 `gh auth login` 이 먼저** 필요하다. 실패하면 경고만 남기고 넘어가므로
수동으로:

```sh
PROJECTS=~/20_Work/01_Asurion/projects
git clone -b feature/atuin-history https://github.com/ggiho/pgcli.git  $PROJECTS/pgcli
git clone -b feature/table-aliases-and-paste-hygiene https://github.com/ggiho/mycli.git $PROJECTS/mycli
uv tool install --editable $PROJECTS/pgcli
uv tool install --editable $PROJECTS/mycli
```

이게 없으면 **justfile 의 `redshift-*` 레시피 5개가 깨진다** — `PGQ_PYTHON`
(justfile:224) 이 pgcli 툴 venv 의 인터프리터를 직접 가리키기 때문이다 (psql 을 안 쓰고
`lib/pgq.py` 가 psycopg 로 붙는다).

### DataGrip 플러그인

바이너리를 관리하지 않으므로 Marketplace 에서 직접 설치.
목록: [datagrip-plugins.md](datagrip-plugins.md)
