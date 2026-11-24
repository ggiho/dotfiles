#!/bin/bash
# justfile 의 DDB_PYTHON(~/.local/share/ddb-venv)을 만든다. ddb-* 레시피가 yaml·boto3 를
# 쓰는데 brew python3 는 업그레이드 때마다 site-packages 가 비어서 uv 관리 파이썬을 쓴다.
set -euo pipefail

VENV="$HOME/.local/share/ddb-venv"

if ! command -v uv >/dev/null 2>&1; then
  echo '[WARN] ddb-venv: uv is missing; rerun this script after installing Brewfile packages.'
  exit 0
fi

[ -x "$VENV/bin/python" ] || uv venv "$VENV" --managed-python --python 3.13 ||
  { echo "[WARN] ddb-venv: venv 생성 실패 -- ddb-* 레시피는 DDB_PYTHON 을 따로 지정해야 합니다"; exit 0; }
uv pip install --python "$VENV/bin/python" pyyaml boto3 ||
  echo "[WARN] ddb-venv: pyyaml·boto3 설치 실패 -- 수동: uv pip install --python $VENV/bin/python pyyaml boto3"
