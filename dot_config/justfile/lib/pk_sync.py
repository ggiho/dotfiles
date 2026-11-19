#!/usr/bin/env python3
"""Compare one table between two MySQL hosts by primary key, and sync the target to it.

Used by mysql-pk-diff / mysql-pk-sync in ~/.config/justfile/justfile.

Why not pt-table-checksum / pt-table-sync or mysql-checksum: the first is master->replica
only, and all of them assume the same schema/table name on both sides. DMS targets rename
tables (ASSET.ASSET -> etldata.asset_ASSET), and a DMS resume that lands inside a source
transaction silently skips the rest of it (2026-10-01: 300,000 deletes lost per table), so
the target has to be checked against the source by PK.

diff
  1. Per side: 256 buckets by PK ORDER -> row count and BIT_XOR of a row hash. The row hash
     is CRC32 of the PK alone, or of the PK plus --columns. With the PK alone this reads the
     smallest index; with columns it reads the whole table.
     Buckets are PK ranges, not CRC32(pk) % 256: a DMS skip leaves one contiguous PK range
     (the source deleted by PK range), and hashing spread it over all 256 buckets so every
     bucket differed. binary/varbinary split on the first byte, integers on the SOURCE's
     MIN..MAX / 256 with anything outside clamped into the first/last bucket (one far-off id
     on the target would otherwise stretch every bucket and put all rows in bucket 0) --
     both make step 2 a PK range scan. char/varchar split on the first byte too, but their
     collation order is not byte order, so step 2 scans the whole index for them.
  2. Only for the buckets that differ: pull (pk, row hash), TARGET FIRST. A row inserted at
     the source and replicated between the two reads then shows up as source-only (harmless)
     instead of target-only, which sync would delete.
  3. Write extra (target only), missing (source only) and changed (same pk, other hash) as
     JSON lines, plus meta.json.
sync
  extra             -> DELETE by pk, after re-checking each chunk against the source
  missing / changed -> read the rows from the source at that moment and
                       INSERT .. ON DUPLICATE KEY UPDATE them (extras go first, so a stale
                       row cannot collide on a secondary unique key)
  then step 2 again on the same buckets, and report what is left.

Connection: SRC_HOST/PORT/USER/PW and TGT_* in the environment (the recipes fill them from
the hosts file and Keychain), so passwords never reach argv. Single-column PKs only.
"""

import argparse
import datetime
import json
import os
import sys
import time
from pathlib import Path

import pymysql
import pymysql.cursors

BUCKETS = 256
LOG = None


def log(msg):
    print(msg, file=sys.stderr)
    if LOG:
        with open(LOG, "a") as f:
            f.write(f"{datetime.datetime.now():%F %T} {msg}\n")


def q(ident):
    return "`" + ident.replace("`", "``") + "`"


def connect(prefix):
    e = os.environ
    conn = pymysql.connect(host=e[f"{prefix}_HOST"], port=int(e[f"{prefix}_PORT"]),
                           user=e[f"{prefix}_USER"], password=e[f"{prefix}_PW"],
                           charset="utf8mb4", autocommit=True, connect_timeout=10)
    with conn.cursor() as c:
        # DMS writes in UTC; read and write TIMESTAMP columns the same way on both sides.
        c.execute("SET SESSION time_zone = '+00:00'")
    return conn


def table_info(conn, name):
    if "." not in name:
        sys.exit(f"schema.table 형식이어야 합니다: {name}")
    schema, table = name.split(".", 1)
    with conn.cursor() as c:
        c.execute("SELECT COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS"
                  " WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s ORDER BY ORDINAL_POSITION", (schema, table))
        rows = c.fetchall()
        c.execute("SELECT COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE"
                  " WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s AND CONSTRAINT_NAME='PRIMARY'"
                  " ORDER BY ORDINAL_POSITION", (schema, table))
        pk = [r[0] for r in c.fetchall()]
    if not rows:
        sys.exit(f"테이블이 없습니다: {name}")
    if len(pk) != 1:
        sys.exit(f"단일 컬럼 PK 만 지원합니다: {name} (PK={pk or '없음'})")
    types = {r[0].lower(): r[1].lower() for r in rows}
    return {"schema": schema, "table": table, "pk": pk[0], "pk_type": types[pk[0].lower()],
            "cols": [r[0] for r in rows]}


def fq(t):
    return f"{q(t['schema'])}.{q(t['table'])}"


def bucketing(src, tgt, s, t):
    ty = s["pk_type"]
    if ty in ("binary", "varbinary"):
        return {"kind": "bytes"}
    if ty in ("char", "varchar"):
        return {"kind": "str"}
    if ty not in ("tinyint", "smallint", "mediumint", "int", "bigint"):
        sys.exit(f"PK 타입 {ty} 는 지원하지 않습니다 (binary/varbinary, char/varchar, 정수만)")
    # Source bounds only, used for both sides so the buckets line up; the target falls back in
    # only when the source is empty.
    for conn, x in ((src, s), (tgt, t)):
        with conn.cursor() as c:
            c.execute(f"SELECT MIN({q(x['pk'])}), MAX({q(x['pk'])}) FROM {fq(x)}")
            lo, hi = c.fetchone()
        if lo is not None:
            break
    lo, hi = (int(lo), int(hi)) if lo is not None else (0, 0)
    w = max(1, -(-(hi - lo + 1) // BUCKETS))
    return {"kind": "int", "lo": lo, "hi": hi, "w": w, "last": (hi - lo) // w}


def bucket_expr(pk, bk):
    if bk["kind"] == "bytes":
        return f"ORD(LEFT({q(pk)}, 1))"
    if bk["kind"] == "str":
        return f"ORD(LEFT(CAST({q(pk)} AS BINARY), 1))"
    return f"FLOOR((LEAST(GREATEST({q(pk)}, {bk['lo']}), {bk['hi']}) - {bk['lo']}) / {bk['w']})"


def range_pred(pk, bk, buckets):
    runs = []  # [1, 2, 3, 7] -> [[1, 3], [7, 7]], one range per run of neighbouring buckets
    for b in sorted(buckets):
        if runs and b == runs[-1][1] + 1:
            runs[-1][1] = b
        else:
            runs.append([b, b])
    p, parts = q(pk), []
    for b1, b2 in runs:
        if bk["kind"] == "str":
            parts.append(f"({bucket_expr(pk, bk)} BETWEEN {b1} AND {b2})")
            continue
        # The first and last bucket stay open-ended: bucket 0 also holds '' / ids below the
        # source MIN, and the last one ids above the source MAX.
        if bk["kind"] == "bytes":
            cond = ([f"{p} >= x'{b1:02X}'"] if b1 > 0 else []) + ([f"{p} < x'{b2 + 1:02X}'"] if b2 < 255 else [])
        else:
            cond = ([f"{p} >= {bk['lo'] + b1 * bk['w']}"] if b1 > 0 else []) + \
                   ([f"{p} <= {bk['lo'] + (b2 + 1) * bk['w'] - 1}"] if b2 < bk["last"] else [])
        parts.append("(" + (" AND ".join(cond) or "TRUE") + ")")
    return " OR ".join(parts)


def hash_expr(pk, cols):
    if not cols:
        return f"CRC32({q(pk)})"
    # ISNULL keeps NULL and '' apart: CONCAT_WS skips NULLs.
    parts = [q(pk)] + [f"{q(c)}, ISNULL({q(c)})" for c in cols]
    return f"CRC32(CONCAT_WS('#', {', '.join(parts)}))"


def bucket_stats(conn, t, cols, bk):
    sql = (f"SELECT {bucket_expr(t['pk'], bk)} b, COUNT(*), BIT_XOR({hash_expr(t['pk'], cols)})"
           f" FROM {fq(t)} GROUP BY b")
    with conn.cursor() as c:
        c.execute(sql)
        return {int(b): (int(n), int(h)) for b, n, h in c.fetchall()}


def pull(conn, t, cols, bk, buckets):
    sql = (f"SELECT {q(t['pk'])}, {hash_expr(t['pk'], cols)} FROM {fq(t)}"
           f" WHERE {range_pred(t['pk'], bk, buckets)}")
    with conn.cursor(pymysql.cursors.SSCursor) as c:
        c.execute(sql)
        return {k: int(h) for k, h in c}


def compare(src, tgt, m, buckets):
    bk = m["bucketing"]
    t = pull(tgt, m["target"], m["target"]["cols_cmp"], bk, buckets)  # target first -- see docstring
    s = pull(src, m["source"], m["source"]["cols_cmp"], bk, buckets)
    extra = sorted(k for k in t if k not in s)
    missing = sorted(k for k in s if k not in t)
    changed = sorted(k for k in t if k in s and t[k] != s[k])
    return extra, missing, changed


def enc(v):
    if isinstance(v, (bytes, bytearray)):
        return {"hex": v.hex().upper()}
    if isinstance(v, (int, str)):
        return v
    return {"str": str(v)}  # datetime, Decimal: MySQL takes the string form back


def dec(v):
    if isinstance(v, dict):
        return bytes.fromhex(v["hex"]) if "hex" in v else v["str"]
    return v


def show(v):
    return v.hex().upper() if isinstance(v, (bytes, bytearray)) else str(v)


def write_keys(path, keys):
    with open(path, "w") as f:
        for k in keys:
            f.write(json.dumps(enc(k)) + "\n")


def read_keys(path):
    if not path.exists():
        return []
    with open(path) as f:
        return [dec(json.loads(line)) for line in f if line.strip()]


def cmd_diff(a):
    src, tgt = connect("SRC"), connect("TGT")
    s, t = table_info(src, a.src_table), table_info(tgt, a.tgt_table or a.src_table)
    if s["pk"].lower() != t["pk"].lower():
        sys.exit(f"PK 가 다릅니다: {s['pk']} / {t['pk']}")
    tmap = {c.lower(): c for c in t["cols"]}
    if a.columns == "*":
        cmp = [c for c in s["cols"] if c.lower() in tmap and c.lower() != s["pk"].lower()]
    else:
        cmp = [c.strip() for c in a.columns.split(",") if c.strip()]
        smap = {c.lower(): c for c in s["cols"]}
        bad = [c for c in cmp if c.lower() not in smap or c.lower() not in tmap]
        if bad:
            sys.exit(f"양쪽에 다 있는 컬럼이 아닙니다: {', '.join(bad)}")
        cmp = [smap[c.lower()] for c in cmp]
    s["cols_cmp"], t["cols_cmp"] = cmp, [tmap[c.lower()] for c in cmp]

    out = Path(a.outdir)
    out.mkdir(parents=True)
    global LOG
    LOG = out / "diff.log"
    s["label"], s["raw"] = os.environ.get("SRC_LABEL", ""), os.environ.get("SRC_RAW", "")
    t["label"], t["raw"] = os.environ.get("TGT_LABEL", ""), os.environ.get("TGT_RAW", "")
    log(f">> {s['label']} {fq(s)}  ->  {t['label']} {fq(t)}   pk={s['pk']}"
        f"   비교={'PK + ' + ','.join(cmp) if cmp else 'PK 존재 여부만'}")

    t0 = time.time()
    bk = bucketing(src, tgt, s, t)
    sb, tb = bucket_stats(src, s, s["cols_cmp"], bk), bucket_stats(tgt, t, t["cols_cmp"], bk)
    diff_b = sorted(b for b in set(sb) | set(tb) if sb.get(b) != tb.get(b))
    with open(out / "buckets.tsv", "w") as f:
        f.write("bucket\tsrc_rows\ttgt_rows\tmatch\n")
        for b in sorted(set(range(BUCKETS)) | set(sb) | set(tb)):
            f.write(f"{b}\t{sb.get(b, (0, 0))[0]}\t{tb.get(b, (0, 0))[0]}\t{'DIFF' if b in diff_b else 'OK'}\n")
    src_n, tgt_n = sum(v[0] for v in sb.values()), sum(v[0] for v in tb.values())
    log(f">> 1단계 {time.time() - t0:.0f}초: 소스 {src_n:,} / 타겟 {tgt_n:,} (차이 {tgt_n - src_n:+,}),"
        f" 다른 구간 {len(diff_b)}/{BUCKETS}" + (f" {diff_b[:12]}{' …' if len(diff_b) > 12 else ''}" if diff_b else ""))

    m = {"created": f"{datetime.datetime.now():%F %T}", "source": s, "target": t, "bucketing": bk,
         "buckets": diff_b, "counts": {"src_rows": src_n, "tgt_rows": tgt_n}}
    extra = missing = changed = []
    if diff_b:
        est = sum(max(sb.get(b, (0, 0))[0], tb.get(b, (0, 0))[0]) for b in diff_b)
        if est > a.max_rows:
            (out / "meta.json").write_text(json.dumps(m, ensure_ascii=False, indent=2))
            sys.exit(f"다른 구간의 행이 {est:,} 개라 PK 를 다 뽑지 않습니다 (max_rows={a.max_rows:,})."
                     " 차이가 테이블 전체에 퍼졌다면 reload 가 낫습니다.")
        t1 = time.time()
        extra, missing, changed = compare(src, tgt, m, diff_b)
        log(f">> 2단계 {time.time() - t1:.0f}초: 구간 {len(diff_b)}개, 약 {est:,} 행 비교")
    write_keys(out / "extra.jsonl", extra)
    write_keys(out / "missing.jsonl", missing)
    write_keys(out / "changed.jsonl", changed)
    m["counts"].update(extra=len(extra), missing=len(missing), changed=len(changed))
    (out / "meta.json").write_text(json.dumps(m, ensure_ascii=False, indent=2))

    print(f"타겟에만 있음 (extra, 삭제 대상)\t{len(extra):,}")
    print(f"소스에만 있음 (missing, 복사 대상)\t{len(missing):,}")
    print(f"값이 다름 (changed, 덮어쓸 대상)\t{len(changed):,}" + ("" if cmp else "\t(columns 를 주지 않아 비교 안 함)"))
    for name, keys in (("extra", extra), ("missing", missing), ("changed", changed)):
        if keys:
            print(f"  {name} 예: {', '.join(show(k) for k in keys[:3])}{' …' if len(keys) > 3 else ''}")
    print(f"결과: {out}")
    if extra or missing or changed:
        print(f">> 계획 보기: j mysql-pk-sync {out}   실행: j mysql-pk-sync {out} true")


def retry(fn, what):
    for attempt in (1, 2, 3):
        try:
            return fn()
        except pymysql.err.OperationalError as e:
            # 1205 lock wait timeout, 1213 deadlock: something else holds the rows (a report's
            # INSERT .. SELECT on 2026-10-01). Back off and try the same chunk again.
            if e.args[0] in (1205, 1213) and attempt < 3:
                log(f"   {what}: {e.args[1]} -- {attempt * 10}초 뒤 다시")
                time.sleep(attempt * 10)
                continue
            raise


def chunks(xs, n):
    for i in range(0, len(xs), n):
        yield xs[i:i + n]


def cmd_sync(a):
    d = Path(a.dir)
    m = json.loads((d / "meta.json").read_text())
    s, t = m["source"], m["target"]
    extra, missing, changed = (read_keys(d / f"{n}.jsonl") for n in ("extra", "missing", "changed"))
    upserts = missing + changed
    print(f"대상\t{t['label']} {fq(t)}  (소스 {s['label']} {fq(s)}, diff {m['created']})")
    print(f"삭제\t{len(extra):,} 행 (묶음 {a.chunk}, 묶음마다 소스에 다시 생겼는지 확인)")
    print(f"복사\t{len(upserts):,} 행 (missing {len(missing):,} + changed {len(changed):,}, 그 순간 소스 값으로)")
    if not extra and not upserts:
        print("고칠 것이 없습니다.")
        return
    if not a.execute:
        return

    global LOG
    LOG = d / "sync.log"
    src, tgt = connect("SRC"), connect("TGT")
    with tgt.cursor() as c:
        c.execute("SELECT @@read_only, @@innodb_read_only")
        if any(c.fetchone()):
            sys.exit(f"타겟이 읽기 전용입니다: {t['label']} -- writer 를 대상으로 diff 를 다시 하세요.")
        c.execute("SET SESSION innodb_lock_wait_timeout = 10")

    deleted = kept = 0
    total = (len(extra) + a.chunk - 1) // a.chunk
    for i, ch in enumerate(chunks(extra, a.chunk), 1):
        with src.cursor() as c:
            c.execute(f"SELECT {q(s['pk'])} FROM {fq(s)} WHERE {q(s['pk'])} IN ({','.join(['%s'] * len(ch))})", ch)
            back = {r[0] for r in c.fetchall()}
        todo = [k for k in ch if k not in back]
        kept += len(ch) - len(todo)
        if todo:
            sql = f"DELETE FROM {fq(t)} WHERE {q(t['pk'])} IN ({','.join(['%s'] * len(todo))})"
            deleted += retry(lambda: tgt.cursor().execute(sql, todo), "delete")
        if i % 25 == 0 or i == total:
            log(f">> 삭제 {i}/{total} 묶음, {deleted:,} 행" + (f" (소스에 다시 있어서 둔 행 {kept:,})" if kept else ""))

    if upserts:
        tmap = {c.lower(): c for c in t["cols"]}
        pairs = [(c, tmap[c.lower()]) for c in table_info(src, f"{s['schema']}.{s['table']}")["cols"] if c.lower() in tmap]
        sel = f"SELECT {', '.join(q(sc) for sc, _ in pairs)} FROM {fq(s)} WHERE {q(s['pk'])} IN "
        ins = (f"INSERT INTO {fq(t)} ({', '.join(q(tc) for _, tc in pairs)}) VALUES ({', '.join(['%s'] * len(pairs))})"
               f" ON DUPLICATE KEY UPDATE "
               + ", ".join(f"{q(tc)}=VALUES({q(tc)})" for _, tc in pairs if tc.lower() != t["pk"].lower()))
        n = min(a.chunk, 500)  # whole rows, possibly with LOBs
        copied = gone = 0
        total = (len(upserts) + n - 1) // n
        for i, ch in enumerate(chunks(upserts, n), 1):
            with src.cursor() as c:
                c.execute(sel + f"({','.join(['%s'] * len(ch))})", ch)
                rows = c.fetchall()
            gone += len(ch) - len(rows)  # deleted at the source since the diff: DMS will follow
            if rows:
                retry(lambda: tgt.cursor().executemany(ins, rows), "upsert")
                copied += len(rows)
            if i % 25 == 0 or i == total:
                log(f">> 복사 {i}/{total} 묶음, {copied:,} 행" + (f" (그새 소스에서 지워진 행 {gone:,})" if gone else ""))

    e2, m2, c2 = compare(src, tgt, m, m["buckets"])
    left = len(e2) + len(m2) + len(c2)
    log(f">> 다시 비교 (같은 구간 {len(m['buckets'])}개): extra {len(e2):,}, missing {len(m2):,}, changed {len(c2):,}")
    if left:
        log(">> 남은 차이는 그사이 바뀐 행일 수 있습니다. 복제가 따라잡은 뒤 mysql-pk-diff 를 다시 해보세요.")
        sys.exit(2)
    log(">> 소스와 같습니다.")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("diff")
    d.add_argument("src_table")
    d.add_argument("tgt_table", nargs="?", default="")
    d.add_argument("--columns", default="")
    d.add_argument("--outdir", required=True)
    d.add_argument("--max-rows", type=int, default=5_000_000)
    s = sub.add_parser("sync")
    s.add_argument("dir")
    s.add_argument("--chunk", type=int, default=2000)
    s.add_argument("--execute", action="store_true")
    a = p.parse_args()
    cmd_diff(a) if a.cmd == "diff" else cmd_sync(a)


if __name__ == "__main__":
    main()
