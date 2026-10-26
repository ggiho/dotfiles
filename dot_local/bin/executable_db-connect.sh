#!/bin/bash

# 데이터베이스 접속 스크립트 (MySQL: mycli / PostgreSQL: pgcli)
# fzf가 필요합니다: brew install fzf

# 서버 목록은 ~/.config/mysql/hosts 에서 관리
# 형식: 표시명:호스트:포트:사용자명[:타입[:DB명]]
#   - 타입 생략 또는 mysql -> mycli 로 접속 (기존 항목 그대로 호환)
#   - 타입이 pg/postgres/postgresql -> pgcli 로 접속
#   - DB명(선택)은 접속 시 기본 DB (mycli -D / pgcli -d)
#   - # 주석(앞 공백 허용)과 빈 줄은 무시
# 목록 읽기/PROD 판별/Keychain 조회는 dbq 와 공용: ~/.local/lib/db-hosts.sh
source "$HOME/.local/lib/db-hosts.sh" || exit 1
if [[ ! -f "$DB_HOSTS_FILE" ]]; then
    echo "호스트 파일이 없습니다: $DB_HOSTS_FILE"
    exit 1
fi

servers=()
while IFS= read -r line; do
    servers+=("$line")
done < <(db_hosts_entries)

# fzf가 설치되어 있는지 확인
if ! command -v fzf &> /dev/null; then
    echo "fzf가 설치되어 있지 않습니다. 설치해주세요: brew install fzf"
    exit 1
fi

# fzf를 사용하여 서버 선택
selected=$(printf '%s\n' "${servers[@]}" | fzf \
    --prompt="DB server> " \
    --height=15 \
    --layout=reverse \
    --header="↑/↓ move · Enter select · Esc cancel" \
    --header-border=none \
    --input-border=none)

# 선택하지 않고 종료한 경우
if [ -z "$selected" ]; then
    echo ""
    exit 0
fi

# 선택한 서버 정보 파싱 (타입/DB명은 선택 필드)
IFS=':' read -r display_name host port user dbtype dbname <<< "$selected"
dbtype="${dbtype:-mysql}"

echo "접속 중: $display_name ($host)"

# PROD면 프롬프트의 호스트(\h)를 빨강으로 (Catppuccin Mocha). 그 외엔 config 색 그대로.
# PROD 판별: 표시명에 PROD가 단어로 있으면 (대소문자 무시, db_is_prod)
host_rgb=""
db_is_prod "$display_name" && host_rgb="243;139;168"

# config의 prompt 줄에서 \h 앞 색만 host_rgb로 바꿔 --prompt 인자로 만든다.
# 프롬프트 원본은 config 한 곳에만 두기 위해 문자열을 여기 복사하지 않는다.
# prompt 값은 따옴표('/") 또는 따옴표 없이, 뒤에 # 주석이 있어도 된다.
# 바꾸지 못하면(config 없음, prompt 줄 없음, \h 바로 앞 색 없음) 경고만 하고 config 프롬프트로 접속.
prompt_args=()
env_prompt() {
    [[ -z "$host_rgb" ]] && return
    local p=""
    [[ -f "$1" ]] && p=$(HOST_RGB="$host_rgb" perl -ne '
        next unless /^prompt\s*=\s*(?:([\x27"])(.*?)\1|([^\x27",#]*?))\s*(?:#.*)?$/;
        $p = defined $1 ? $2 : $3;
        print $p if $p =~ s/\\x1b\[[\d;]*m(?=\\h)/\\x1b[38;2;$ENV{HOST_RGB}m/;
        exit;' "$1")
    if [[ -n "$p" ]]; then
        prompt_args=(--prompt "$p")
    else
        echo "경고: $1 의 prompt 에서 \\h 앞 색을 찾지 못해 PROD 색 없이 접속합니다." >&2
    fi
}

# macOS Keychain에서 비밀번호 조회 (MySQL/PG 공용, 없으면 프롬프트로 폴백)
DB_PASSWORD=$(db_password "$user")

case "$dbtype" in
    pg|postgres|postgresql)
        env_prompt "$HOME/.config/pgcli/config"
        if [[ -n "$DB_PASSWORD" ]]; then
            PGPASSWORD="$DB_PASSWORD" pgcli -h "$host" -p "$port" -U "$user" ${dbname:+-d "$dbname"} "${prompt_args[@]}"
        else
            echo "Keychain에 비밀번호가 없습니다. 저장하려면:"
            echo "  security add-generic-password -s \"mysql-db-connect\" -a \"$user\" -w"
            pgcli -h "$host" -p "$port" -U "$user" ${dbname:+-d "$dbname"} "${prompt_args[@]}" -W
        fi
        echo "PostgreSQL 접속을 종료했습니다."
        ;;
    *)
        env_prompt "$HOME/.myclirc"
        if [[ -n "$DB_PASSWORD" ]]; then
            MYSQL_PWD="$DB_PASSWORD" mycli -h "$host" -P "$port" -u "$user" ${dbname:+-D "$dbname"} "${prompt_args[@]}"
        else
            echo "Keychain에 비밀번호가 없습니다. 저장하려면:"
            echo "  security add-generic-password -s \"mysql-db-connect\" -a \"$user\" -w"
            mycli -h "$host" -P "$port" -u "$user" ${dbname:+-D "$dbname"} "${prompt_args[@]}" -p
        fi
        echo "MySQL 접속을 종료했습니다."
        ;;
esac
