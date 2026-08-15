#!/bin/zsh
# chezmoi run_once (apply 후 1회): 새 머신에서 노트 워크플로우 부트스트랩 실행.
# 실제 로직은 dot_local/bin/executable_notes-bootstrap.sh 에 있음(수동 재실행 가능).
# 멱등적이라 기존 머신에서 재실행돼도 전부 skip 처리됨.
echo "[chezmoi run_once] 노트 워크플로우 부트스트랩…"
"$HOME/.local/bin/notes-bootstrap.sh"
