# 창 관리 구성 (AeroSpace + SketchyBar)

이상한 일이 생기면 **어느 층의 문제인지**부터 본다. 층은 다섯 개다.

| 층 | 하는 일 | 위치 |
|---|---|---|
| AeroSpace | 창 배치, 워크스페이스, 단축키, 앱 규칙 | `aerospace/aerospace.toml` |
| SketchyBar | 위쪽 막대(워크스페이스 번호, 앱 아이콘, CPU/MEM, 시계 …) | `sketchybar/sketchybarrc` |
| wsbar | 막대에 번호·아이콘·강조를 그리고, 아래 "감시"를 담당하는 상주 데몬 | `sketchybar/helper/wsbar.py` |
| 헬퍼 | `winframes`, `appwatch`, `sysstat`(막대용) / `resize`, `keepbelow`, `summon`, `sync-mode.sh`(AeroSpace용) | `sketchybar/helper/`, `aerospace/` |
| Kanata + TOTEM | 홈로우 모드(`s`=Alt, `d`=Cmd, `f`=Shift, `a`=Ctrl), 방향키 | `kanata/` |

## 워크스페이스

| 번호 | 모니터 | 용도 |
|---|---|---|
| 6, 7 | 왼쪽 외부 | 7 브라우저(Chrome), 6 여분(Outlook) |
| 8 | 오른쪽 외부 | 터미널(WezTerm, `term` 모드) |
| 9, 0 | 내장 화면 | 9 작업 도구(DataGrip, Obsidian, 아코디언), 0 메신저(Slack) |

모니터가 없으면 `main`으로 되돌아간다. 이름은 TOTEM 숫자 레이어의 `y u i o p` = `6 7 8 9 0`과 맞다.

## 키 (Alt = `s` 홀드)

| 키 | 동작 |
|---|---|
| `alt-hjkl` | 타일 창 포커스 이동(플로팅 제외). 8번(`term` 모드)에서는 tmux가 받음 |
| `alt-cmd-hjkl` | 창 이동(전체화면이면 먼저 해제) |
| `alt-shift-hjkl` | 크기 조절(꾹 누르면 반복) |
| `alt-y u i o p` | 워크스페이스 6 7 8 9 0 |
| `alt-cmd-y u i o p` | 창을 그 워크스페이스로 보내고 따라감 |
| `alt-tab` / `alt-space` | 직전 워크스페이스 / 직전 창 |
| `alt-t b m c` | WezTerm / Chrome / Outlook / Slack(개인 PC는 KakaoTalk, 지금 워크스페이스로 불러옴) |
| `alt-cmd-t` | 플로팅과 타일 전환 |
| `alt-cmd-\` | 타일 방향(가로/세로) 전환 |
| `alt-cmd-m` | 전체화면 |
| `alt-cmd-;` | 서비스 모드(`esc`로 나옴) |
| `alt-cmd-,` `alt-cmd-.` | 포커스를 이전/다음 모니터로 |

tmux 팝업은 `M-e`.

## 앱 규칙 (먼저 맞는 하나만)

Chrome → 7, WezTerm → 8, DataGrip·Obsidian → 9(세로 아코디언), Slack → 0, Outlook → 6(타일),
KakaoTalk → 플로팅(워크스페이스 이동 없음), 나머지 전부 → 플로팅. 플로팅은 막대 밑으로 내려서 연다(`keepbelow`).

## wsbar의 감시

| 감시 | 하는 일 |
|---|---|
| 활성화 보정(`GUARD`) | Dock·Raycast 등으로 앱이 활성화됐는데 AeroSpace 포커스가 다른 곳이면 맞춤 |
| 흔들림 감시 | 타일 창 프레임이 계속 뒤집히면(앱 최소 크기 때문) 그 창을 플로팅으로 |
| 막대 밑 감시 | 제목줄이 막대 밑에 들어간 창을 `keepbelow`로 내림 |
| 모니터 감시 | macOS가 아는 모니터와 SketchyBar가 아는 모니터가 다르면 SketchyBar 재시작 |
| 아이콘 재확인 | 창·앱이 사라진 뒤 AeroSpace 목록이 늦으면 1초 뒤 한 번 더 확인 |

## 고칠 수 없는 것 (프로그램의 한계)

- 혼자 있는 창은 반 화면으로 못 만든다(빈 칸 개념이 없음).
- 같은 워크스페이스에 타일 창이 새로 들어오면 전체화면이 풀린다.
- 창 최소 크기 합이 모니터 폭을 넘으면 타일이 삐져나온다. 창을 나누거나 아코디언으로 둔다.
- 잠금 해제 직후 막대가 잠깐 안 보일 수 있다(스스로 복구됨).
- AeroSpace 0.21.3은 플로팅 창이 있는 곳에서 포커스 키를 아주 빠르게 연타하면 죽을 수 있다(이슈 #1311). `alt-hjkl`에 `--ignore-floating`을 줘서 피한다.

## 먼저 해볼 것

| 증상 | 명령 |
|---|---|
| 키가 아무것도 안 먹음 / AeroSpace가 없음 | `open -a AeroSpace` (죽었으면 크래시 리포트: `ls -t ~/Library/Logs/DiagnosticReports/AeroSpace-*.ips \| head -1`) |
| 설정을 바꿨음 | `aerospace reload-config` |
| 막대가 없거나 이상함 | 로컬 `launchctl kickstart -k gui/$(id -u)/sh.brew.sketchybar`, 원격은 `homebrew.mxcl.sketchybar` |
| 아이콘·강조가 틀림 | `~/.config/sketchybar/helper/wsbar-ensure.sh restart` |
| 한 워크스페이스의 창이 겹치거나 엉킴 | `aerospace flatten-workspace-tree --workspace N` 후 `aerospace layout --workspace N --root h_tiles` 후 `aerospace balance-sizes --workspace N` |
| 터미널(8번)에서 `alt-hjkl`이 tmux로 안 감 | `~/.config/aerospace/sync-mode.sh` |
| 창이 엉뚱한 워크스페이스로 감 | `aerospace move-node-to-workspace --window-id <id> <번호>` |

## 로그와 디버그

- `/tmp/wsbar.<uid>.log` (wsbar), `/tmp/sketchybar-ws-apps.shake.log`(흔들림·모니터 재시작 기록)
- `/opt/homebrew/var/log/sketchybar/sketchybar.err.log`
- 이벤트까지 보려면 `touch /tmp/wsbar-debug-on` 후 `wsbar-ensure.sh restart`. 끝나면 파일을 지운다.

## 새 Mac / 원격

`chezmoi apply` 한 번으로 설정과 헬퍼(Swift 빌드 포함)가 들어간다. 작업 PC는 `~/.config/chezmoi/chezmoi.toml`의
`[data] work = true`로 구분한다(앱 규칙과 `alt-c` 대상이 달라진다).
