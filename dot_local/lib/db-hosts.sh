# db-connect.sh / dbq 공용: 서버 목록 읽기, PROD 판별, Keychain 비밀번호 조회
# source 해서 사용. macOS /bin/bash 3.2 호환.
#
# 서버 목록 형식: 표시명:호스트:포트:사용자명[:타입[:DB명]]
#   - 타입 생략 또는 mysql -> MySQL, pg/postgres/postgresql -> PostgreSQL
#   - DB명(선택)은 접속 시 기본 DB (MySQL/PG 공통)

DB_HOSTS_FILE="$HOME/.config/mysql/hosts"

# 주석(앞 공백 허용 #)과 빈 줄/공백만 있는 줄을 뺀 서버 줄
db_hosts_entries() {
    grep -vE '^[[:space:]]*(#|$)' "$DB_HOSTS_FILE"
}

# 표시명에 PROD가 단어로 들어 있으면 참 (대소문자 무시)
#   "Horizon PROD", "prod", "PROD-ro" -> PROD / "PREPROD", "Production" -> 아님
db_is_prod() {
    local re='(^|[^[:alnum:]])[Pp][Rr][Oo][Dd]($|[^[:alnum:]])'
    [[ "$1" =~ $re ]]
}

# macOS Keychain 비밀번호 (서비스 "mysql-db-connect", account=사용자). 없으면 빈 출력.
db_password() {
    security find-generic-password -s "mysql-db-connect" -a "$1" -w 2>/dev/null
}
