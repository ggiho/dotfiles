#!/bin/bash
# GUI 에서 바꾼 DataGrip 설정을 정본으로 되받는다 (배포의 역방향).
#
# 이 파일들의 실질적 편집 주체는 IDE 다. 그래서 정본을 손으로 고치는 대신,
# GUI 에서 설정을 바꾼 뒤 이 스크립트를 돌려 정본을 갱신하고 커밋한다.
#
#   대상:  가장 최신 DataGrip*/{options,keymaps,colors} 중 정본에 이미 있는 파일만
#   정본:  ~/.local/share/chezmoi 의 소스 (chezmoi add 로 반영)
#
# "정본에 있는 파일만" 가져오는 이유: options/ 에는 60개가 넘는 파일이 있고
# 대부분 창 위치·최근 목록 같은 로컬 상태다. 추적 대상은 의도적으로 고른
# 13개뿐이므로, 목록을 늘리려면 chezmoi add 로 명시적으로 추가한다.
set -e

CANON="$HOME/.config/jetbrains/datagrip"
JB="$HOME/Library/Application Support/JetBrains"

[ -d "$CANON" ] || { echo "정본이 없습니다: $CANON" >&2; exit 1; }

VER=$(/bin/ls -d "$JB"/DataGrip* 2>/dev/null | sed 's#.*/DataGrip##' | sort -V | tail -1)
[ -n "$VER" ] || { echo "DataGrip 설정 디렉터리를 찾지 못했습니다" >&2; exit 1; }
SRC="$JB/DataGrip$VER"
echo "원본: DataGrip$VER"

changed=0
while IFS= read -r f; do
  rel="${f#$CANON/}"
  if [ ! -f "$SRC/$rel" ]; then
    echo "  [없음] $rel -- DataGrip$VER 에 없어 건너뜀"
    continue
  fi
  if ! /usr/bin/cmp -s "$SRC/$rel" "$f"; then
    /bin/cp "$SRC/$rel" "$f"
    echo "  갱신  $rel"
    changed=$((changed+1))
  fi
done < <(/usr/bin/find "$CANON" -type f)

if [ "$changed" -eq 0 ]; then
  echo "변경 없음 -- 정본이 이미 최신입니다."
  exit 0
fi

echo "$changed개 갱신. chezmoi 소스에 반영합니다."
chezmoi add "$CANON"
echo
echo "다음: chezmoi diff 로 확인한 뒤 커밋하세요."
echo "  chezmoi cd && git add -A && git commit"
