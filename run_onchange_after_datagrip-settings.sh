#!/bin/bash
# DataGrip 설정을 버전 디렉터리로 배포한다.
#
# JetBrains 는 설정을 ~/Library/Application Support/JetBrains/DataGrip<버전>/ 에
# 두므로 경로에 버전이 박힌다. chezmoi 는 소스 경로 이름의 템플릿을 해석하지
# 않아서(실측 확인) DataGrip{{ .ver }}/ 같은 방식이 불가능하다. 그래서 정본을
# 버전 중립 경로에 두고 이 스크립트가 실제 버전 디렉터리로 복사한다.
#
#   정본:   ~/.config/jetbrains/datagrip/{options,keymaps,colors}/
#   대상:   가장 최신 DataGrip* 하나 (낡은 버전은 건드리지 않는다)
#
# 심볼릭 링크가 아니라 복사인 이유: 이 파일들의 런타임 소유자는 IDE 다. 종료할
# 때 자기 메모리 상태로 다시 쓰므로 링크가 일반 파일로 교체될 수 있고, 무엇보다
# 어느 방향이 정본인지 흐려진다. GUI 에서 바꾼 설정을 정본으로 되받는 것은
# datagrip-settings-capture.sh 가 명시적으로 담당한다.
set -e

CANON="$HOME/.config/jetbrains/datagrip"
JB="$HOME/Library/Application Support/JetBrains"

[ -d "$CANON" ] || { echo "  [skip] 정본 없음: $CANON"; exit 0; }
[ -d "$JB" ]    || { echo "  [skip] JetBrains 설정 디렉터리 없음 -- DataGrip 미설치"; exit 0; }

# 최신 버전 디렉터리 하나. 버전 비교는 sort -V 로 한다 (2026.10 > 2026.9).
TARGET=$(/bin/ls -d "$JB"/DataGrip* 2>/dev/null | sed 's#.*/DataGrip##' | sort -V | tail -1)
[ -n "$TARGET" ] || { echo "  [skip] DataGrip 버전 디렉터리를 찾지 못함"; exit 0; }
DEST="$JB/DataGrip$TARGET"

# 실행 중이면 건드리지 않는다. IDE 는 종료할 때 설정을 자기 상태로 덮어쓰므로
# 지금 복사해도 사라지고, 최악의 경우 IDE 가 읽는 중인 파일과 경합한다.
# pgrep -f 를 쓰는 이유: `ps | grep <패턴>` 은 grep 자신의 argv 에 패턴이 들어가
# 항상 매치된다 -- 그러면 DataGrip 이 꺼져 있어도 영원히 skip 한다. pgrep 은
# 자기 프로세스를 제외한다.
if /usr/bin/pgrep -f "DataGrip[.]app/Contents/MacOS/datagrip" >/dev/null 2>&1; then
  echo "  [skip] DataGrip 실행 중 -- 종료 후 'chezmoi apply' 또는 이 스크립트를 다시 실행하세요"
  echo "         대상이었던 경로: $DEST"
  exit 0
fi

echo "  DataGrip$TARGET 로 설정 배포"
copied=0
while IFS= read -r f; do
  rel="${f#$CANON/}"
  /bin/mkdir -p "$DEST/$(dirname "$rel")"
  if ! /usr/bin/cmp -s "$f" "$DEST/$rel"; then
    /bin/cp "$f" "$DEST/$rel" && copied=$((copied+1))
  fi
done < <(/usr/bin/find "$CANON" -type f)
echo "  갱신한 파일: $copied개 (동일한 파일은 건너뜀)"
