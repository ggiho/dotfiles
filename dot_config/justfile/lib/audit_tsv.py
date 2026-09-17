#!/usr/bin/env python3
"""Turn Aurora MySQL audit-log lines on stdin into TSV for lib/table.py.

The Aurora audit log is CSV:

    timestamp,serverhost,username,host,connectionid,queryid,operation,database,'query',retcode

The query field is single-quoted and routinely contains commas, so it cannot be
split on the delimiter -- csv.reader with a single-quote quotechar handles it.
timestamp is microseconds since the epoch.

Environment:
  CELL=N   truncate the query column to N characters (0 = leave it alone)
  TZ       applies to the rendered timestamps as usual
"""

import csv
import os
import sys
from datetime import datetime

FIELDS = 10


def when(raw: str) -> str:
    try:
        return datetime.fromtimestamp(int(raw) / 1_000_000).strftime("%m-%d %H:%M:%S")
    except (ValueError, OSError):
        return raw


def main() -> int:
    cell = int(os.environ.get("CELL") or 0)
    out = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    out.writerow(["time", "user", "from", "db", "op", "query"])

    reader = csv.reader(sys.stdin, quotechar="'", doublequote=False, escapechar="\\")
    seen = 0
    for row in reader:
        # Short rows are continuation lines from a multi-line statement; the audit
        # log does not escape newlines inside the query field.
        if len(row) < FIELDS - 2:
            continue
        ts, _server, user, frm, _conn, _qid, op, db = row[:8]
        query = row[8] if len(row) > 8 else ""
        query = " ".join(query.split())
        if cell and len(query) > cell:
            query = query[: cell - 1] + "…"
        out.writerow([when(ts), user, frm, db or "-", op, query])
        seen += 1

    if seen == 0:
        print("(no matching audit entries)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
