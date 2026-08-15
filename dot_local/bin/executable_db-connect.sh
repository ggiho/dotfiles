#!/bin/bash

# 데이터베이스 접속 스크립트 (MySQL: mycli / PostgreSQL: pgcli)
# fzf가 필요합니다: brew install fzf

# 서버 목록은 ~/.config/mysql/hosts 에서 관리
# 형식: 표시명:호스트:포트:사용자명[:타입[:DB명]]
#   - 타입 생략 또는 mysql -> mycli 로 접속 (기존 항목 그대로 호환)
#   - 타입이 pg/postgres/postgresql -> pgcli 로 접속
#   - DB명(선택)은 pg 접속 시에만 사용
HOSTS_FILE="$HOME/.config/mysql/hosts"
if [[ ! -f "$HOSTS_FILE" ]]; then
    echo "호스트 파일이 없습니다: $HOSTS_FILE"
    exit 1
fi

servers=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    servers+=("$line")
done < "$HOSTS_FILE"

# fzf가 설치되어 있는지 확인
if ! command -v fzf &> /dev/null; then
    echo "fzf가 설치되어 있지 않습니다. 설치해주세요: brew install fzf"
    exit 1
fi

# fzf를 사용하여 서버 선택
selected=$(printf '%s\n' "${servers[@]}" | fzf \
    --prompt="DB 서버 선택: " \
    --height=15 \
    --layout=reverse \
    --border \
    --header="↑/↓: 이동, Enter: 선택, Esc: 취소")

# 선택하지 않고 종료한 경우
if [ -z "$selected" ]; then
    echo ""
    exit 0
fi

# 선택한 서버 정보 파싱 (타입/DB명은 선택 필드)
IFS=':' read -r display_name host port user dbtype dbname <<< "$selected"
dbtype="${dbtype:-mysql}"

echo "접속 중: $display_name ($host)"

# macOS Keychain에서 비밀번호 조회 (MySQL/PG 공용, 없으면 프롬프트로 폴백)
DB_PASSWORD=$(security find-generic-password -s "mysql-db-connect" -a "$user" -w 2>/dev/null)

case "$dbtype" in
    pg|postgres|postgresql)
        # Redshift는 client_encoding을 'UNICODE'로 보고 -> Python 코덱에 없어 에러.
        # PGCLIENTENCODING=utf-8 로 libpq가 utf-8 협상하도록 강제.
        export PGCLIENTENCODING=utf-8
        if [[ -n "$DB_PASSWORD" ]]; then
            PGPASSWORD="$DB_PASSWORD" pgcli -h "$host" -p "$port" -U "$user" ${dbname:+-d "$dbname"}
        else
            echo "Keychain에 비밀번호가 없습니다. 저장하려면:"
            echo "  security add-generic-password -s \"mysql-db-connect\" -a \"$user\" -w"
            pgcli -h "$host" -p "$port" -U "$user" ${dbname:+-d "$dbname"} -W
        fi
        echo "PostgreSQL 접속을 종료했습니다."
        ;;
    *)
        if [[ -n "$DB_PASSWORD" ]]; then
            MYSQL_PWD="$DB_PASSWORD" mycli -h "$host" -P "$port" -u "$user"
        else
            echo "Keychain에 비밀번호가 없습니다. 저장하려면:"
            echo "  security add-generic-password -s \"mysql-db-connect\" -a \"$user\" -w"
            mycli -h "$host" -P "$port" -u "$user" -p
        fi
        echo "MySQL 접속을 종료했습니다."
        ;;
esac
