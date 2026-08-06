# kanata 설정/설치 메모

이 디렉터리는 macOS에서 `kanata`를 사용하기 위한 설정과 자동 실행 파일을 담고 있다.

검증 기준:
- 확인일: 2026-03-17
- 환경: macOS 26.2, Apple Silicon
- kanata: v1.11.0

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

### 4. `compiled to never allow cmd`

의미:
- kanata의 외부 명령 실행용 `cmd` action이 비활성화된 빌드라는 뜻
- macOS Command 키(`lmet`, `rmet`) 매핑과는 다른 의미

### 5. 외부 키보드(Totem 등) a홀드+hjkl 방향키가 안 됨

배경:
- Totem(ZMK) 펌웨어는 a홀드를 `ctrl`로 보낸다. 그래서 a홀드+hjkl = `ctrl+hjkl`이 전송된다.
- kanata가 이 `ctrl+hjkl`을 방향키로 바꿔야 하는데, 그러려면 (1) kanata가 외부 키보드를
  grab 해야 하고 (2) `ctrl+hjkl → 방향키` 매핑이 있어야 한다.
- 현재 `kanata.kbd`는 `macos-dev-names-exclude`로 모든 물리 키보드를 grab 하고,
  `defoverrides`로 `(lctl h/j/k/l) → (left/down/up/rght)`를 처리한다.

확인:
- `sudo kanata --list`로 외부 키보드가 보이는지, VirtualHIDKeyboard 이름이 무엇인지 본다.
- grab 충돌(Karabiner grabber)이 있으면 `### 4` 아래 grabber 비활성화를 먼저 한다.

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

원인:
- TOTEM(블루투스 ZMK)이 붙었다 떨어질 때, kanata가 이전 grab을 close 못한 채 재open을
  시도 → `exclusive access` 충돌. 그 상태에서 modifier(Ctrl) release가 전달 안 돼 stuck.
- 재부팅/절전 복귀 후 특히 잘 난다.

대응 (정답, 2026-07-14):
- **kanata가 TOTEM을 grab하지 않게 제외.** `kanata.kbd`의 `macos-dev-names-exclude`에 `"TOTEM"` 추가.
  (chezmoi 관리 → 소스에서 수정 후 `chezmoi apply` → `kanata --check` → 재시작.)
- 내장 키보드는 kanata 리매핑, TOTEM은 ZMK 펌웨어 자체 리매핑 사용.
- exclude 이름은 TOTEM 연결 상태에서 `sudo kanata --list`로 정확히 확인 (기본은 `TOTEM`).

> [!danger] "연결 후 kickstart로 재grab"은 하지 말 것
> TOTEM을 kanata로 다시 grab하려는 시도 자체가 위 충돌/Ctrl stuck의 원인이다. `### 5`의
> "kanata로 TOTEM 방향키 처리" 방식은 폐기하고, TOTEM은 exclude한다.

긴급 (Ctrl stuck 중): `sudo launchctl bootout system/local.kanata` → kanata 꺼지면 키보드 즉시 정상.

## 지금 구성에서 기억할 것

- 평소엔 터미널에서 직접 `sudo kanata ...`를 띄울 필요 없다.
- `launchd` 서비스만 살아 있으면 부팅 후 자동 실행 가능하다.
- 문제 생기면 먼저 중복 실행 여부와 로그를 본다.

## 참고 링크

- Kanata releases: https://github.com/jtroo/kanata/releases
- Kanata configuration guide: https://github.com/jtroo/kanata/wiki/Configuration-guide
- Karabiner DriverKit VirtualHIDDevice: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice
- Homebrew formula: https://formulae.brew.sh/formula/kanata
