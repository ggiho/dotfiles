#!/usr/bin/env python3
"""Run one SQL statement against Postgres/Redshift and print TSV for lib/table.py.

psql is not installed here, so the pgcli tool venv's psycopg is used instead --
run this with that interpreter (the recipes do).

Connection comes from the standard PG* environment variables. PGCLIENTENCODING is
forced to utf-8 because Redshift reports its client_encoding as "UNICODE", which
psycopg rejects with "codec not available in Python: 'UNICODE'".

Usage:
    pgq.py "SELECT ..." [param ...]
"""

import os
import sys

os.environ.setdefault("PGCLIENTENCODING", "utf-8")

import psycopg  # noqa: E402  (must follow the encoding default)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: pgq.py <sql> [param ...]", file=sys.stderr)
        return 2
    sql, params = sys.argv[1], tuple(sys.argv[2:])

    try:
        with psycopg.connect(connect_timeout=25) as conn, conn.cursor() as cur:
            cur.execute(sql, params or None)
            if cur.description is None:
                print(cur.statusmessage or "OK", file=sys.stderr)
                return 0
            print("\t".join(c.name for c in cur.description))
            for row in cur:
                cells = []
                for v in row:
                    if v is None:
                        cells.append("")
                    else:
                        # Tabs and newlines would break the TSV contract.
                        cells.append(" ".join(str(v).split()))
                print("\t".join(cells))
    except psycopg.Error as e:
        print(str(e).splitlines()[0], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
