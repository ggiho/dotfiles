# 새 Mac에서 수동으로 해야 하는 것

`chezmoi apply` + `brew bundle`로 끝나지 않는 항목만 모았다. 각 항목에 **왜 자동화하지 않았는지**를 같이 적어둔다 — 대부분 macOS TCC(권한) 아니면 공개 repo에 넣을 수 없는 값이다.

## 1. macOS 권한 (TCC — 스크립트로 부여 불가)

| 대상 | 위치 | 안 하면 |
|------|------|---------|
| terminal-notifier 알림 | System Settings → Notifications → terminal-notifier | Claude 작업완료 알림이 **조용히** 실패. `osascript` 폴백으로 알림은 뜨지만 **클릭해도 pane 점프 안 됨** |
| kanata Input Monitoring | System Settings → Privacy & Security → Input Monitoring | 키 리맵 동작 안 함 |
| kanata Accessibility | System Settings → Privacy & Security → Accessibility | 위와 동일 |

terminal-notifier 권한은 CLI로 리셋할 수 없다. `tccutil reset UserNotification fr.julienxx.oss.terminal-notifier`는
최신 macOS에서 거부된다(2026-09 확인: `tccutil: Failed to reset ...`, rc=70). 한 번 거부 상태가 되면
System Settings에서 직접 켜는 방법밖에 없다.

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

## 3. 앱 안에서 설치해야 하는 것

| 대상 | 문서 |
|------|------|
| DataGrip 플러그인 | `docs/datagrip-plugins.md` |

## 확인 순서

```bash
chezmoi apply                                   # dotfiles 배치 + run_once/run_onchange 실행
brew bundle --file ~/.config/brew/Brewfile      # 패키지 (terminal-notifier 포함)
# → 위 1·2·3 수동 항목 처리
```

Claude 알림이 동작하는지 확인:

```bash
tail -5 ~/.claude/hooks/turn-notify.log   # 턴마다 2줄. gate2 판단 근거와 생략 사유가 남는다
```

## 갱신 방법

`.chezmoiignore`에 경로를 새로 추가했거나, 권한이 필요한 도구를 새로 넣었으면 이 문서도 같이 갱신한다.
"설치했는데 왜 안 되지"를 다시 디버깅하지 않으려고 만든 문서다.
