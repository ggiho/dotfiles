# 새 Mac에서 수동으로 해야 하는 것

`chezmoi apply` + `brew bundle`로 끝나지 않는 항목만 모았다. 각 항목에 **왜 자동화하지 않았는지**를 같이 적어둔다 — 대부분 macOS TCC(권한) 아니면 공개 repo에 넣을 수 없는 값이다.

## 1. macOS 권한 (TCC — 스크립트로 부여 불가)

| 대상 | 위치 | 안 하면 |
|------|------|---------|
| terminal-notifier 알림 | System Settings → Notifications → terminal-notifier | Claude 작업완료 알림이 **조용히** 실패. `osascript` 폴백으로 알림은 뜨지만 **클릭해도 pane 점프 안 됨** |
| Claude Code Notifier 알림 | System Settings → Notifications → Claude Code Notifier | 알림 아이콘이 Claude 로 안 바뀜. 기존 terminal-notifier 로 폴백되므로 **기능 손실은 없다** |
| kanata Input Monitoring | System Settings → Privacy & Security → Input Monitoring | 키 리맵 동작 안 함 |
| kanata Accessibility | System Settings → Privacy & Security → Accessibility | 위와 동일 |

terminal-notifier 권한은 CLI로 리셋할 수 없다. `tccutil reset UserNotification fr.julienxx.oss.terminal-notifier`는
최신 macOS에서 거부된다(2026-09 확인: `tccutil: Failed to reset ...`, rc=70). 한 번 거부 상태가 되면
System Settings에서 직접 켜는 방법밖에 없다.

알림 아이콘을 Claude 로 바꾸려면 별도 번들이 필요하다(`~/.local/bin/claude-notifier-build.sh`가 만든다).
macOS 는 알림 아이콘을 **보낸 번들**에서 가져오고 이를 덮어쓸 API 가 없어서(terminal-notifier 3.0.0 에서
`-appIcon`·`-sender` 제거됨) 번들을 복사하는 것이 공식 우회책이다. 새 bundle id 라 권한도 새로 받아야 한다.

kanata는 권한 관련 증상·트러블슈팅이 길어서 별도 문서에 있다 → `dot_config/kanata/README.md`

## 2. repo에 넣지 않는 파일 (비밀·사내 정보)

이 repo는 공개다. 아래는 `.chezmoiignore`로 제외했으니 새 머신에서 직접 넣어야 한다.

| 경로 | 내용 | 복구 방법 |
|------|------|-----------|
| `~/.claude/settings.json` | LLM 게이트웨이 URL, `apiKeyHelper` 경로, 모델 지정 | 수동 작성. **알림 hook 3개는 `run_onchange_after_claude-notify-hooks.sh`가 자동 병합**하므로 `env`·`model`·`apiKeyHelper`만 채우면 된다 |
| `~/.local/bin/asurion-llm-gateway/api-key-helper` | 6.4MB 사내 바이너리 | 사내 배포처에서 받기 (chezmoi 미관리) |
| `~/.config/mysql/hosts` | DB 서버 목록·계정 | 수동 배치. 이 파일만 넣으면 `db` / `dbq` 동작 |
| `~/.config/justfile/prod.just` | PROD 인프라 레시피 (내부 호스트명) | 로컬 전용 |
| `~/.soluto_dm.env` | 자격증명 | 수동 |
| `~/.config/{redshift,gh,gcloud,mycli,opencode}/` | 각 도구 인증 토큰 | 각 도구로 재로그인 (`gh auth login`, `gcloud auth login` 등) |
| `~/.claude/settings.local.json`, `~/.claude.json` | Claude Code 로컬 상태·권한 허용목록 | 사용하면서 자동 축적 |
| 키체인 `mysql-db-connect` | DB 비밀번호 (hosts 의 user 마다 하나) | `security add-generic-password -s "mysql-db-connect" -a "<db-user>" -w`. 없으면 `db`/`dbq`/justfile 의 DB 레시피가 전부 멈춘다 |
| atuin 로그인 | 셸 히스토리 동기화 (`https://api.atuin.sh/`) | `atuin login`. 안 하면 로컬 전용으로 동작 |

## 3. repo로 재현 안 되는 설치 — pgcli / mycli 포크

PyPI 본이 아니라 **로컬 포크의 editable 설치**다. Brewfile에 `uv "pgcli"` / `uv "mycli"`를
적으면 업스트림이 깔려 패치가 사라지므로 일부러 빼 뒀다.

| 도구 | repo (private) | 브랜치 | 패치 |
|------|----------------|--------|------|
| pgcli | `ggiho/pgcli` | `feature/atuin-history` | atuin 백엔드 쿼리 히스토리 + Up-arrow 피커 |
| mycli | `ggiho/mycli` | `feature/table-aliases-and-paste-hygiene` | `\t`·`\d`·`\dn`·`\list` psql 스타일 별칭, 붙여넣기/source/편집 SQL의 invisible 문자 제거 |

`run_once_bootstrap.sh`가 clone + `uv tool install --editable`까지 해주지만 **private repo라
`gh auth login`이 먼저**다. 실패하면 경고만 남기고 넘어가므로 수동으로:

```bash
PROJECTS=~/20_Work/01_Asurion/projects
git clone -b feature/atuin-history https://github.com/ggiho/pgcli.git $PROJECTS/pgcli
git clone -b feature/table-aliases-and-paste-hygiene https://github.com/ggiho/mycli.git $PROJECTS/mycli
uv tool install --editable $PROJECTS/pgcli
uv tool install --editable $PROJECTS/mycli
```

빠지면 **justfile의 `redshift-*` 5개가 깨진다** — `PGQ_PYTHON`(justfile:224)이 pgcli 툴 venv의
인터프리터를 직접 가리키기 때문이다(psql을 안 쓰고 `lib/pgq.py`가 psycopg로 붙는다).
`.myclirc`의 favorite 쿼리도 포크의 `{{ kv.d }}` 명명 파라미터를 쓰므로 업스트림에서는 안 먹는다.

## 4. 앱 안에서 설치해야 하는 것

| 대상 | 문서 |
|------|------|
| DataGrip 플러그인 | `docs/datagrip-plugins.md` |

## 확인 순서

```bash
chezmoi apply                                   # dotfiles 배치 + run_once/run_onchange 실행
brew bundle --file ~/.config/brew/Brewfile      # 패키지 (terminal-notifier 포함)
# → 위 1·2·3·4 수동 항목 처리
```

`chezmoi apply`가 돌리는 스크립트에는 부작용이 있다. 기존 머신에서 무심코 돌리기 전에:

| 스크립트 | 부작용 |
|----------|--------|
| `run_once_bootstrap.sh` | **`sudo` 암호 입력**(kanata launchd), `dockutil --remove all`로 **Dock 재구성**, `brew bundle install`이 구버전 패키지를 **업그레이드** |
| `run_onchange_macos-defaults.sh` | `defaults write` 102줄(키 반복·트랙패드 등). 일부는 재로그인 후 적용 |
| `run_once_after_notes-bootstrap.sh` | **실행 중인 Obsidian을 종료시킨다**(`obsidian.json`을 Obsidian이 종료 시 덮어쓰므로). 멱등적이라 재실행은 안전 |
| `run_onchange_after_claude-notify-hooks.sh` | 멱등적. `jq` 없으면 조용히 건너뜀 |

부작용을 피하고 파일만 반영하려면:

```bash
chezmoi apply --exclude scripts                                  # 파일만
chezmoi apply --include scripts --exclude files                   # 스크립트만
brew bundle install --no-upgrade --file ~/.config/brew/Brewfile   # 업그레이드 없이 빠진 것만
```

Claude 알림이 동작하는지 확인:

```bash
tail -5 ~/.claude/hooks/turn-notify.log   # 턴마다 2줄. gate2 판단 근거와 생략 사유가 남는다
```

## 갱신 방법

`.chezmoiignore`에 경로를 새로 추가했거나, 권한이 필요한 도구를 새로 넣었으면 이 문서도 같이 갱신한다.
"설치했는데 왜 안 되지"를 다시 디버깅하지 않으려고 만든 문서다.
