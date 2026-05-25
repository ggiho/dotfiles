#!/usr/bin/env python3
import re
import sys
from typing import List

SKIP_USERS = {
    ("rdsadmin", "localhost"),
    ("mysql.session", "localhost"),
    ("mysql.sys", "localhost"),
    ("mysql.infoschema", "localhost"),
}

SKIP_ROLE_NAMES = {
    "rds_superuser_role",
}

# Aurora/RDS에서 그대로 주면 자주 문제 되는 privilege들
# 환경마다 더 줄이거나 늘릴 수 있음
STRIP_PRIVILEGES = {
    "SUPER",
    "FILE",
    "SHUTDOWN",
    "BINLOG_ADMIN",
    "BINLOG_ENCRYPTION_ADMIN",
    "CONNECTION_ADMIN",
    "ENCRYPTION_KEY_ADMIN",
    "GROUP_REPLICATION_ADMIN",
    "INNODB_REDO_LOG_ENABLE",
    "PERSIST_RO_VARIABLES_ADMIN",
    "REPLICATION_APPLIER",
    "REPLICATION_SLAVE_ADMIN",
    "RESOURCE_GROUP_ADMIN",
    "RESOURCE_GROUP_USER",
    "SERVICE_CONNECTION_ADMIN",
    "SESSION_VARIABLES_ADMIN",
    "SYSTEM_USER",
    "SYSTEM_VARIABLES_ADMIN",
    "TABLE_ENCRYPTION_ADMIN",
    "TELEMETRY_LOG_ADMIN",
    "XA_RECOVER_ADMIN",
    "AUDIT_ABORT_EXEMPT",
    "AUDIT_ADMIN",
    "AUTHENTICATION_POLICY_ADMIN",
    "BACKUP_ADMIN",
    "CLONE_ADMIN",
    "FIREWALL_EXEMPT",
    "FLUSH_OPTIMIZER_COSTS",
    "FLUSH_STATUS",
    "FLUSH_TABLES",
    "FLUSH_USER_RESOURCES",
    "PASSWORDLESS_USER_ADMIN",
    "ROLE_ADMIN",
    "SET_USER_ID",
    "APPLICATION_PASSWORD_ADMIN",
}

RE_CREATE_ROLE = re.compile(
    r"^CREATE ROLE IF NOT EXISTS `(?P<role>[^`]+)`;?$",
    re.IGNORECASE,
)

RE_CREATE_USER = re.compile(
    r"^CREATE USER IF NOT EXISTS `(?P<user>[^`]+)`@`(?P<host>[^`]+)`;?$",
    re.IGNORECASE,
)

RE_ALTER_USER = re.compile(
    r"^ALTER USER `(?P<user>[^`]+)`@`(?P<host>[^`]+)` (?P<rest>.*);$",
    re.IGNORECASE,
)

RE_GRANT_ROLE = re.compile(
    r"^GRANT `(?P<role>[^`]+)`@`(?P<rhost>[^`]+)` TO `(?P<user>[^`]+)`@`(?P<host>[^`]+)`;?$",
    re.IGNORECASE,
)

RE_GRANT_PRIV = re.compile(
    r"^GRANT (?P<privs>.+?) ON (?P<scope>.+?) TO `(?P<user>[^`]+)`@`(?P<host>[^`]+)`(?P<tail> WITH GRANT OPTION)?;?$",
    re.IGNORECASE,
)


def should_skip_user(user: str, host: str) -> bool:
    if (user, host) in SKIP_USERS:
        return True
    return False


def should_skip_role(role: str) -> bool:
    return role in SKIP_ROLE_NAMES


def normalize_privilege_list(priv_text: str) -> str:
    privs = [p.strip() for p in priv_text.split(",")]
    kept: List[str] = []
    for p in privs:
        up = p.upper()
        if up in STRIP_PRIVILEGES:
            continue
        kept.append(p)
    if not kept:
        return ""
    return ", ".join(kept)


def rewrite_alter_user(line: str, pending_default_roles: List[str]) -> str | None:
    m = RE_ALTER_USER.match(line)
    if not m:
        return line

    user = m.group("user")
    host = m.group("host")
    rest = m.group("rest")

    if should_skip_user(user, host):
        return None

    # DEFAULT ROLE 제거 후 별도 SET DEFAULT ROLE 생성
    # 예:
    # ALTER USER ... AS '*HASH' DEFAULT ROLE `role_backend`@`%` REQUIRE NONE ...
    # ->
    # ALTER USER ... AS '*HASH' REQUIRE NONE ...
    # SET DEFAULT ROLE `role_backend`@`%` TO `user`@`host`;

    role_match = re.search(
        r"\s+DEFAULT ROLE\s+`([^`]+)`@`([^`]+)`\s+",
        rest,
        re.IGNORECASE,
    )
    if role_match:
        role_name = role_match.group(1)
        role_host = role_match.group(2)
        rest = re.sub(
            r"\s+DEFAULT ROLE\s+`([^`]+)`@`([^`]+)`\s+",
            " ",
            rest,
            count=1,
            flags=re.IGNORECASE,
        )
        if not should_skip_role(role_name):
            pending_default_roles.append(
                f"SET DEFAULT ROLE `{role_name}`@`{role_host}` TO `{user}`@`{host}`;"
            )

    # 내부 계정이면 제외
    if user.startswith("mysql.") or user == "rdsadmin":
        return None

    return f"ALTER USER `{user}`@`{host}` {rest};"


def rewrite_grant_priv(line: str) -> str | None:
    m = RE_GRANT_PRIV.match(line)
    if not m:
        return line

    user = m.group("user")
    host = m.group("host")
    privs = m.group("privs")
    scope = m.group("scope")
    tail = m.group("tail") or ""

    if should_skip_user(user, host):
        return None

    # role에 대한 grant privilege도 동일 규칙 적용
    filtered = normalize_privilege_list(privs)

    # 다 제거되면 statement 생략
    if not filtered:
        return None

    return f"GRANT {filtered} ON {scope} TO `{user}`@`{host}`{tail};"


def rewrite_grant_role(line: str) -> str | None:
    m = RE_GRANT_ROLE.match(line)
    if not m:
        return line

    role = m.group("role")
    rhost = m.group("rhost")
    user = m.group("user")
    host = m.group("host")

    if should_skip_role(role):
        return None
    if should_skip_user(user, host):
        return None

    return f"GRANT `{role}`@`{rhost}` TO `{user}`@`{host}`;"


def rewrite_create_user(line: str) -> str | None:
    m = RE_CREATE_USER.match(line)
    if not m:
        return line

    user = m.group("user")
    host = m.group("host")

    if should_skip_user(user, host):
        return None
    if user.startswith("mysql.") or user == "rdsadmin":
        return None

    return line


def rewrite_create_role(line: str) -> str | None:
    m = RE_CREATE_ROLE.match(line)
    if not m:
        return line

    role = m.group("role")
    if should_skip_role(role):
        return None

    return line


def sanitize(lines: List[str]) -> List[str]:
    out: List[str] = []
    pending_default_roles: List[str] = []

    for raw in lines:
        line = raw.rstrip("\n")

        if not line.strip():
            out.append("")
            continue

        # 주석은 대부분 유지, 특정 내부 계정 블록 주석은 그냥 둬도 무방
        if line.lstrip().startswith("--"):
            # 굳이 지울 필요는 없지만 너무 헷갈리는 내부 계정은 주석도 생략 가능
            if any(x in line for x in [
                "'rdsadmin'@'localhost'",
                "'mysql.session'@'localhost'",
                "'mysql.sys'@'localhost'",
                "'mysql.infoschema'@'localhost'",
                "'rds_superuser_role'@'%'",
            ]):
                continue
            out.append(line)
            continue

        cur = line
        cur = rewrite_create_role(cur)
        if cur is None:
            continue

        cur = rewrite_create_user(cur)
        if cur is None:
            continue

        cur = rewrite_alter_user(cur, pending_default_roles)
        if cur is None:
            continue

        cur = rewrite_grant_role(cur)
        if cur is None:
            continue

        cur = rewrite_grant_priv(cur)
        if cur is None:
            continue

        # rds_superuser_role 관련 직접 grant/comment가 남아 있으면 제거
        if "rds_superuser_role" in cur:
            continue

        out.append(cur)

    # 문서 끝에 default role 구문 추가
    if pending_default_roles:
        out.append("")
        out.append("-- Default roles rewritten for Aurora/RDS compatibility")
        out.extend(pending_default_roles)

    return out


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.sql> <output.sql>", file=sys.stderr)
        return 1

    infile = sys.argv[1]
    outfile = sys.argv[2]

    with open(infile, "r", encoding="utf-8") as f:
        lines = f.readlines()

    sanitized = sanitize(lines)

    with open(outfile, "w", encoding="utf-8") as f:
        f.write("\n".join(sanitized))
        f.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
