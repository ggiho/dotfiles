---
name: db-query
description: Run non-interactive SQL queries against the user's registered Asurion databases (Horizon/DataMart/SOHO/OnTheGo/Nova MySQL + Redshift) without being given any connection info. Connection details come from the machine (~/.config/mysql/hosts + macOS Keychain). Use whenever the user asks to query, check, count, inspect, or look up data in one of these databases (e.g. "Redshift에서 row 수 세줘", "Horizon DEV에서 이 테이블 조회", "check datamart"). The `dbq` helper resolves host/port/user/password/client automatically.
---

# DB Query (dbq)

## Overview

The `dbq` command runs a SQL query against a named database from the user's
server list and prints the result. **You do not need connection strings,
hosts, ports, or passwords** — `dbq` reads them from the machine:

- Server list: `~/.config/mysql/hosts` (format `표시명:host:port:user[:type[:db]]`)
- Password: macOS Keychain, service `mysql-db-connect`, account = the entry's user
- Client is auto-selected: MySQL entries → `mysql -e`, `pg`/`postgres` entries → `psql -c`

It is the non-interactive counterpart of the user's interactive `db` command.

## Usage

```bash
dbq --list                        # list available server display names
dbq "<display name>" "<SQL>"      # run a query, print result to stdout
```

Examples:
```bash
dbq Redshift "SELECT count(*) FROM datamart.etldata.claims_claimdetail"
dbq "Horizon DEV" "SELECT * FROM claims.ClaimDetail LIMIT 5"
dbq "OnTheGo SQA" "SHOW TABLES FROM otg"
```

## How to use it (agent workflow)

1. If unsure which databases exist, run `dbq --list` first.
2. Pick the display name. Matching is **case-insensitive and partial**, but
   exact match wins. A partial name that hits several servers (e.g. `Horizon`)
   errors and lists the candidates — be more specific (`Horizon DEV`).
3. Run `dbq "<name>" "<SQL>"`. `dbq` prints `[dbq] <name> -> host:port (type)`
   to stderr so you can confirm which server you hit.

## Important notes

- **MySQL entries usually have no default database.** Fully-qualify tables as
  `schema.table` (e.g. `claims.ClaimDetail`), or the query fails with "No
  database selected". (An entry may pin a default DB as its 6th field.)
- **Redshift.** The database is `datamart`. Redshift is case-sensitive and needs
  three-part table names and double-quoted UPPERCASE columns — for the full
  conversion rules use the **`mysql-to-redshift`** skill before writing Redshift SQL.
- **No read-only guard.** `dbq` will run whatever SQL you pass. Fully-prod
  databases are unreachable from local anyway, but still prefer read-only
  (`SELECT`/`SHOW`/`EXPLAIN`) unless the user explicitly asks to modify data,
  and confirm destructive statements first.
- **Output.** MySQL prints an ASCII table (`--table`); psql prints its aligned
  default. For machine-parseable output add flags to the SQL/session as needed
  (e.g. MySQL `--batch -N` would require editing the call — usually the default
  table is fine to read).

## Prerequisites (already set up on this machine)

- `mysql` client (Homebrew `mysql-client`)
- `psql` (Homebrew `libpq`; `dbq` finds it even if keg-only)
- Keychain password stored:
  `security add-generic-password -s "mysql-db-connect" -a "<user>" -w`

## Related

- `db-connect.sh` / `db` alias — interactive fzf + mycli/pgcli version (same hosts + Keychain).
- `mysql-to-redshift` skill — MySQL→Redshift SQL conversion rules.
- `athena-query` skill — for Athena (`asurion_insurance`) instead of these RDBs.
