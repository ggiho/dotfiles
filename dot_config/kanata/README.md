# kanata 설정/설치 메모

이 디렉터리는 macOS에서 `kanata`를 사용하기 위한 설정과 자동 실행 파일을 담고 있다.

검증 기준:
- 확인일: 2026-03-17
- 환경: macOS 26.2, Apple Silicon
- kanata: v1.12.0 이상 (v1.11.0은 plist의 `--release-grab-on-lock`을 몰라서 못 뜬다 → 문제 9)

## 현재 파일 구성

- `kanata.kbd`: 실제 kanata 설정 파일
- `launchd/local.kanata.vhid.plist`: Karabiner VirtualHID daemon용 LaunchDaemon
- `launchd/local.kanata.plist`: kanata용 LaunchDaemon
- `scripts/install-launchd.sh`: launchd 설치/재시작 스크립트
- `scripts/uninstall-launchd.sh`: launchd 제거 스크립트

## 핵심 정리

macOS에서 kanata를 쓰려면 아래가 필요했다.

1. `kanata` 바이너리 설치
2. `Karabiner DriverKit VirtualHIDDevice` 설치
3. VirtualHID 드라이버 활성화
4. VirtualHID daemon 실행
5. `sudo` 또는 root `launchd`로 kanata 실행
6. 필요 시 Input Monitoring / Accessibility 권한 허용
7. 중복 실행 금지

중요 포인트:
- macOS에서는 Karabiner VirtualHID를 통해 가상 키보드 출력이 이뤄진다.
- root 권한 없이 실행하면 pqrs root-only 소켓 접근 문제로 실패할 수 있다.
- kanata를 두 개 띄우면 `exclusive access and device already open` 에러가 난다.
- `compiled to never allow cmd`의 `cmd`는 쉘 명령 실행 action을 뜻하고, macOS Command 키(`lmet`)와는 다른 의미다.

## 새 PC에 적용할 때 (chezmoi 환경)

`chezmoi apply`는 **파일만 배포**한다. 데몬 설치와 권한 허용은 해주지 않으므로, apply 직후에는 설정 파일은 최신인데 kanata는 안 떠 있는 상태가 정상이다. 아래를 순서대로 직접 한다.

1. **의존성**: `brew install kanata` + Karabiner VirtualHIDDevice (아래 "처음부터 다시 설치하는 순서" 1~2).
   - kanata는 **v1.12.0 이상**이어야 한다. plist의 `--release-grab-on-lock`은 v1.12.0부터 있는 옵션이다. 이미 설치돼 있어도 `kanata --version`으로 확인하고 낮으면 `brew upgrade kanata` (→ 문제 9).
   - VHID 드라이버 버전도 kanata가 지원하는 것과 맞아야 한다 (→ 문제 7).
2. **데몬 설치**: `sudo ~/.config/kanata/scripts/install-launchd.sh`
   - 부작용: 그 PC의 Karabiner-Elements grabber와 Karabiner 쪽 VHID 데몬을 끈다 (`bootout` + `disable`). 그 PC에서 Karabiner 규칙을 쓰고 있었다면 이 시점부터 동작하지 않는다.
   - 이 시점에는 권한이 없어서 kanata가 떴다가 바로 죽고 launchd가 재시작을 반복한다. 정상이다.
3. **권한 두 개를 그 PC 화면에서 허용**한다. SSH로는 못 한다 (macOS 개인정보 보호 권한은 GUI 승인만 된다).
   - System Settings → Privacy & Security → **Input Monitoring** → `kanata` 켜기
   - System Settings → Privacy & Security → **Accessibility** → `kanata` 켜기
   - 둘이 한꺼번에 안 나온다. kanata는 Input Monitoring을 통과해야 Accessibility를 요청하므로, 첫 번째를 켜고 재시작해야 두 번째 에러가 보인다. 하나 켰는데 또 권한 에러가 나도 정상 진행 중이다.
   - 목록에 없으면 `+`로 `/opt/homebrew/bin/kanata`를 추가한다.
   - kanata를 업그레이드하거나 옮긴 뒤에는 macOS가 옛 경로를 기억한다. 기존 `kanata` 항목을 지우고 다시 추가한다.
4. **재시작**: 권한을 켠 뒤 `sudo launchctl kickstart -k system/local.kanata`
5. **확인**: `tail /tmp/kanata.out.log`에서 `driver connected: true`, `driver version matched: true`, `keyboard grabbed`가 보이면 끝. 권한 에러는 `tail /tmp/kanata.err.log`에 나온다.

SSH로 원격 PC를 작업할 때:
- `sudo`는 비밀번호를 TTY로 받으므로 `ssh -t`(또는 `-tt`)로 접속한다.
- 비대화형 셸의 PATH에는 `/opt/homebrew/bin`이 없다. `export PATH=/opt/homebrew/bin:$PATH`를 먼저 한다.

## 처음부터 다시 설치하는 순서

### 0. 기존 인스턴스 정리

```bash
sudo launchctl bootout system/local.kanata 2>/dev/null || true
sudo launchctl bootout system/local.kanata.vhid 2>/dev/null || true
sudo pkill -x kanata 2>/dev/null || true
sudo killall Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || true
```

필요하면 이전 launchd 파일도 제거:

```bash
sudo rm -f /Library/LaunchDaemons/local.kanata.plist
sudo rm -f /Library/LaunchDaemons/local.kanata.vhid.plist
```

### 1. kanata 설치

#### Homebrew 사용

```bash
brew install kanata
```

또는 GitHub release 바이너리를 직접 설치한다.

설치 확인:

```bash
which kanata
kanata --version
```

### 2. Karabiner VirtualHID 설치

`Karabiner DriverKit VirtualHIDDevice`를 설치한다.

설치 후 활성화:

```bash
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
```

### 3. VirtualHID daemon 실행

수동 테스트용:

```bash
sudo '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon'
```

### 4. 설정 파일 준비

이 디렉터리의 설정 파일:

```bash
/Users/giho.seong/.config/kanata/kanata.kbd
```

문법 검증:

```bash
kanata --check --cfg /Users/giho.seong/.config/kanata/kanata.kbd
```

### 5. 수동 실행으로 먼저 검증

```bash
sudo kanata --cfg /Users/giho.seong/.config/kanata/kanata.kbd
```

정상 신호 예시:
- `Starting kanata proper`
- `driver connected: true`

### 6. 자동 실행으로 고정

이 저장소에 있는 스크립트 사용:

```bash
sudo /Users/giho.seong/.config/kanata/scripts/install-launchd.sh
```

이 스크립트가 하는 일:
- launchd plist를 `/Library/LaunchDaemons`에 설치
- VirtualHID activate 수행
- `local.kanata.vhid` / `local.kanata` 등록 및 재시작
- 로그 일부 출력

## 자동 실행 관련 명령

### 재시작

```bash
sudo launchctl kickstart -k system/local.kanata.vhid
sudo launchctl kickstart -k system/local.kanata
```

### 상태 확인

```bash
sudo launchctl print system/local.kanata | head -80
sudo launchctl print system/local.kanata.vhid | head -80
```

### 중지

```bash
sudo launchctl bootout system/local.kanata
sudo launchctl bootout system/local.kanata.vhid
```

### 제거

```bash
sudo /Users/giho.seong/.config/kanata/scripts/uninstall-launchd.sh
```

## 로그 위치

```bash
/tmp/kanata.out.log
/tmp/kanata.err.log
/tmp/kanata-vhid.out.log
/tmp/kanata-vhid.err.log
```

확인 예시:

```bash
sed -n '1,120p' /tmp/kanata.out.log
sed -n '1,120p' /tmp/kanata.err.log
```

## 자주 만난 문제와 의미

### 1. root-only 소켓 접근 실패

예시:

```text
Permission denied [/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server]
```

의미:
- root 권한 또는 root launchd 구성이 안 된 상태

대응:
- `sudo kanata ...`로 테스트
- 또는 LaunchDaemon으로 실행

### 2. 장치가 이미 열려 있음

예시:

```text
exclusive access and device already open
```

의미:
- 이미 다른 kanata 인스턴스가 키보드를 grab 중

대응:
- 수동 실행 중이면 launchd 서비스 중지
- launchd 서비스 사용 중이면 수동 실행 종료
- 항상 한 인스턴스만 실행

### 3. not permitted

예시:

```text
IOHIDDeviceOpen error: (iokit/common) not permitted
```

의미:
- macOS 개인정보 보호 권한 이슈 가능성

확인할 곳:
- System Settings → Privacy & Security → Input Monitoring
- System Settings → Privacy & Security → Accessibility

kanata v1.12.0은 빠진 권한을 에러에 직접 적어준다 (`/tmp/kanata.err.log`):

```text
failed to open keyboard device(s): kanata needs macOS Input Monitoring permission.
failed to open keyboard device(s): kanata needs macOS Accessibility permission.
```

- **두 권한이 모두 필요**하고, Input Monitoring → Accessibility 순서로 하나씩 나온다.
- 둘 다 켰는데도 계속 나오면 옛 경로가 박힌 것이다. `brew upgrade`나 이동 후에 흔하다. 기존 `kanata` 항목을 삭제하고 현재 바이너리를 다시 추가한 뒤 `sudo launchctl kickstart -k system/local.kanata`.
- 새 PC 순서는 "새 PC에 적용할 때" 참고.

### 4. `compiled to never allow cmd`

의미:
- kanata의 외부 명령 실행용 `cmd` action이 비활성화된 빌드라는 뜻
- macOS Command 키(`lmet`, `rmet`) 매핑과는 다른 의미

### 5. TOTEM에서 A를 누른 채 H/J/K/L을 눌러도 방향키가 나오지 않음

TOTEM의 ZMK 펌웨어는 A를 길게 누르면 왼쪽 Ctrl을 보낸다. 현재 Kanata는 내장 키보드와 TOTEM 입력을 모두 처리하며, `defoverrides`에서 왼쪽 Ctrl + H/J/K/L을 각각 ←/↓/↑/→로 바꾼다. 이 규칙은 내장 키보드의 물리 왼쪽 Ctrl에도 적용된다.

TOTEM을 연결하고 `sudo kanata --list`로 장치 이름을 확인한다. 현재 `macos-dev-names-exclude`에는 Karabiner 가상 키보드만 들어 있다. 가상 키보드 이름이 달라졌다면 문제 6을, 블루투스 재연결 후 Ctrl이 눌린 채 남는다면 문제 8을 참고한다.

### 6. 외부 키보드가 안 되거나 글자가 멋대로 입력됨 (VirtualHIDKeyboard 버전 불일치)

원인:
- `kanata.kbd`의 `macos-dev-names-exclude`에 `"Karabiner DriverKit VirtualHIDKeyboard 1.8.0"`
  처럼 **버전이 박혀 있다**. kanata는 이름/hash 정확 매칭만 지원하고 패턴 매칭이 없다.
- Karabiner 드라이버를 업데이트해 VirtualHIDKeyboard 버전이 바뀌면, exclude가 안 먹혀
  kanata가 자기 가상 출력을 다시 입력으로 잡는다(출력 루프) → 글자가 멋대로 입력되거나
  외부 키보드 동작이 깨진다.

대응:
- `sudo kanata --list`로 현재 VirtualHIDKeyboard의 정확한 이름(버전 포함)을 확인한다.
- `kanata.kbd`의 `macos-dev-names-exclude` 항목을 그 이름으로 맞춘다.
- 새 기기에 적용할 때도 동일하게 버전 이름을 확인해 맞춰야 한다.

### 7. `connect_failed asio.system:2` 무한 반복 (VHID driver가 너무 최신 = IPC 불일치)

예시:

```text
connect_failed asio.system:2
Waiting for DriverKit virtual keyboard... (n.n s/10.0s)
output backend unavailable — releasing input devices
```

감별 (이 케이스 확정 조건):
- kanata·VHID 데몬 프로세스 둘 다 정상 실행 중
- grabber 프로세스 없음 (`pgrep -fl "karabiner_console_user_server|Karabiner-Core-Service"` 비어있음)
- 권한 로그(`Input Monitoring`/`Accessibility`) 안 뜸
- 순수하게 kanata가 데몬 소켓에 못 붙음 (`asio.system:2` = ENOENT)

원인:
- Karabiner VirtualHIDDevice driver가 kanata 지원 버전보다 **최신으로 자동 업데이트**됨.
- kanata의 번들 `karabiner-driverkit` crate(1.11.0=0.2.0, 1.12.0=0.3.1)는 특정 driver 릴리스
  IPC로 빌드되는데, pqrs가 minor 버전 사이에 protocol을 바꿔서 더 새 driver는 안 붙는다.
- kanata 지원 driver 버전은 `docs/setup-macos.md`에 명시 (2026-07 기준 `v6.2.0`).

진단:

```bash
tail /var/log/karabiner/virtual_hid_device_service.log   # version / driver_version / client_protocol_version
strings /opt/homebrew/bin/kanata | grep karabiner-driverkit   # kanata의 crate 버전
curl -fsSL https://raw.githubusercontent.com/jtroo/kanata/v1.12.0/docs/setup-macos.md | grep -i 'supported driver'
```

대응 (검증됨 2026-07-12, 재부팅 불필요):
- **kanata 다운그레이드는 소용없다** (1.11.0/1.12.0 둘 다 실패). driver 쪽을 맞춰야 한다.
- VHID를 지원버전(v6.2.0)으로 다운그레이드. **실제 터미널에서** 실행 (Claude Code `!`는 sudo 비번 못 받음).
  명령은 **한 줄로** (긴 경로가 줄바꿈되면 뒤 인자가 별도 명령이 돼 실패).

```bash
# pkg: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v6.2.0
sudo installer -pkg /tmp/Karabiner-DriverKit-VirtualHIDDevice-6.2.0.pkg -target /
sudo /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager forceActivate
```

- forceActivate 직후 데몬이 v6.2.0으로 재동작 (로그 `virtual_hid_keyboard_ready_ is changed: true`, 소켓이 `<hash>.sock`로 변경).
- 그다음 kanata만 재시작: `sudo launchctl kickstart -k system/local.kanata`
- 정상 로그: `driver connected: true` / `driver version matched: true` / `virtual_hid_keyboard_ready true` / `keyboard grabbed`.
- deactivate·재부팅 모두 불필요했다.

### 8. 외부 블루투스 키보드(TOTEM)에서 Ctrl이 눌린 채 stuck / 글자 멋대로 입력

예시:

```text
IOHIDDeviceOpen error: (iokit/common) exclusive access and device already open TOTEM
```
증상: `999111;;;` 처럼 멋대로 찍히고, 홈로우모드의 Ctrl(A홀드)이 눌린 채 멈춘다.

절전 복귀나 블루투스 재연결 직후 위 오류와 함께 Ctrl이 눌린 채 남은 사례가 있다. 현재 설정은 TOTEM을 계속 처리한다. 장치가 없어도 Kanata가 실행을 유지하도록 `macos-continue-if-no-devs-found yes`를 쓰고, 화면 잠금 시에는 launchd의 `--release-grab-on-lock` 옵션으로 장치 점유를 해제한다.

Ctrl이 눌린 채 입력을 방해하면 `sudo launchctl bootout system/local.kanata`로 Kanata 서비스를 중지할 수 있다. 이때 내장 키보드의 Kanata 매핑도 함께 꺼진다.

**재연결 때마다 문제가 반복될 때의 우회 방법**은 TOTEM을 Kanata 처리 대상에서 제외하는 것이다. TOTEM을 연결한 상태에서 `sudo kanata --list`로 이름을 확인한 뒤 chezmoi 소스의 `macos-dev-names-exclude`에 그 이름을 추가하고 배포한다. 이 경우 TOTEM에는 ZMK 매핑만 적용되므로 문제 5의 Ctrl + H/J/K/L 방향키 변환도 사라진다.

### 9. `unexpected argument '--release-grab-on-lock' found` (exit 2 무한 재시작)

증상:
- `sudo launchctl print system/local.kanata`가 `state = spawn scheduled`, `last exit code = 2`, `runs`가 계속 증가
- `/tmp/kanata.err.log`에 아래가 반복되고 `/tmp/kanata.out.log`는 비어 있음

```text
error: unexpected argument '--release-grab-on-lock' found
```

원인:
- kanata가 v1.12.0보다 낮다 (v1.11.0에는 이 옵션이 없다). plist는 chezmoi로 최신이 배포되니 PC마다 kanata 버전이 어긋나기 쉽다.

대응:
- `brew upgrade kanata` 후 `sudo launchctl kickstart -k system/local.kanata`
- plist에서 옵션을 빼는 방식은 쓰지 않는다. 설치본(`/Library/LaunchDaemons`)만 달라져서 다음 `install-launchd.sh`에 원복된다.
- 업그레이드하면 바이너리 경로가 바뀌므로 권한을 다시 켜야 할 수 있다 (→ 문제 3).

## 지금 구성에서 기억할 것

- 평소엔 터미널에서 직접 `sudo kanata ...`를 띄울 필요 없다.
- `launchd` 서비스만 살아 있으면 부팅 후 자동 실행 가능하다.
- 문제 생기면 먼저 중복 실행 여부와 로그를 본다.

## 참고 링크

- Kanata releases: https://github.com/jtroo/kanata/releases
- Kanata configuration guide: https://github.com/jtroo/kanata/wiki/Configuration-guide
- Karabiner DriverKit VirtualHIDDevice: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice
- Homebrew formula: https://formulae.brew.sh/formula/kanata
