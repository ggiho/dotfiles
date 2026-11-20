"""Data-only mapped imports for mysqlsh-load. No third-party dependencies.

Executed with mysqlsh --py --file; normal Python can run --check-log and tests.
See docs/mysqlsh-load.md for the mapping format and partial-import semantics.
"""

import json
import re
import sys
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def identifier(value):
    require(
        isinstance(value, str) and value and "\x00" not in value,
        f"잘못된 식별자: {value!r}",
    )
    return "`" + value.replace("`", "``") + "`"


def unique_object(pairs):
    obj = {}
    for key, value in pairs:
        require(key not in obj, f"중복 JSON 키: {key}")
        obj[key] = value
    return obj


def read_json(path):
    with path.open(encoding="utf-8") as stream:
        return json.load(stream, object_pairs_hook=unique_object)


def dump_file(root, name):
    require(
        isinstance(name, str)
        and name not in ("", ".", "..")
        and "/" not in name
        and "\\" not in name,
        f"잘못된 덤프 파일명: {name!r}",
    )
    path = root / name
    require(path.resolve().parent == root, f"덤프 외부 파일: {name}")
    return path


def dump_index(root, meta):
    """Read the dump's own names, including its encoded file basenames."""
    index = {}
    for schema in meta["schemas"]:
        schema_base = meta["basenames"][schema]
        schema_meta = read_json(dump_file(root, schema_base + ".json"))
        for table in schema_meta["tables"]:
            key = f"{schema}.{table}"
            require(key not in index, f"모호한 스키마/테이블 이름: {key}")
            base = schema_meta["basenames"][table]
            index[key] = (schema, table, base)
    bases = [value[2] for value in index.values()]
    require(len(bases) == len(set(bases)), "중복 덤프 파일명")
    return index


def mapping_files(indir, working_dir=None):
    """Find mapping JSONs beside the dump or cwd, each at most one directory deep."""
    found = []
    seen = set()
    roots = [Path(indir).resolve(), Path(working_dir or Path.cwd()).resolve()]
    for root in dict.fromkeys(roots):
        for candidate in sorted(set(root.glob("*.json")) | set(root.glob("*/*.json"))):
            path = candidate.resolve()
            if (
                path in seen
                or path.name in ("@.json", "@.done.json")
                or "\n" in str(path)
            ):
                continue
            seen.add(path)
            try:
                config = read_json(path)
            except (OSError, ValueError):
                continue
            if not isinstance(config, dict) or not set(config) <= {
                "tables",
                "schema_snapshot",
                "target_schema",
            }:
                continue
            tables = config.get("tables")
            if (
                isinstance(tables, dict)
                and tables
                and all(
                    isinstance(spec, dict)
                    and set(spec) <= {"exclude_columns", "column_map", "target_table"}
                    for spec in tables.values()
                )
            ):
                found.append(path)
    return found


def build_plan(indir, mapping, target_schema, threads, duplicates):
    require(duplicates in ("error", "skip", "replace"), "잘못된 duplicates 값")
    require(isinstance(threads, int) and threads > 0, "threads는 양수여야 합니다")
    root = Path(indir).resolve()
    meta = read_json(root / "@.json")
    done = read_json(root / "@.done.json")
    require(meta.get("tzUtc") is True, "UTC 덤프(tzUtc=true)가 필요합니다")
    config = mapping if isinstance(mapping, dict) else read_json(Path(mapping))
    require(
        isinstance(config, dict)
        and "tables" in config
        and set(config) <= {"tables", "schema_snapshot", "target_schema"},
        '매핑 형식: {"tables": {"source_schema.table": {...}}}',
    )
    tables = config["tables"]
    require(
        isinstance(tables, dict) and tables, "tables는 비어 있지 않은 객체여야 합니다"
    )
    index = dump_index(root, meta)
    owners = {value[2]: key for key, value in index.items()}
    require(
        set(tables) <= set(index), f"덤프에 없는 테이블: {set(tables) - set(index)}"
    )
    files = {key: [] for key in tables}
    for name in done["chunkFileBytes"]:
        path = dump_file(root, name)
        candidates = [
            base for base in owners if name.startswith((base + "@", base + "."))
        ]
        if candidates:
            owner = owners[max(candidates, key=len)]
            if owner in files:
                require(path.is_file(), f"덤프 청크 없음: {name}")
                files[owner].append(str(path))
    plan = []
    destinations = set()
    for source, spec in tables.items():
        require(
            isinstance(spec, dict)
            and set(spec) <= {"exclude_columns", "column_map", "target_table"},
            f"{source}: 허용된 키는 exclude_columns, column_map, target_table입니다",
        )
        schema, table, base = index[source]
        table_meta = read_json(dump_file(root, base + ".json"))
        require(table_meta.get("includesData") is True, f"{source}: 데이터가 없는 덤프")
        opts = table_meta["options"]
        source_columns = opts["columns"]
        require(
            isinstance(source_columns, list)
            and source_columns
            and all(isinstance(c, str) for c in source_columns)
            and len(set(source_columns)) == len(source_columns),
            f"{source}: 지원하지 않는 덤프 컬럼 메타데이터",
        )
        exclude = spec.get("exclude_columns", [])
        rename = spec.get("column_map", {})
        require(
            isinstance(exclude, list)
            and all(isinstance(c, str) for c in exclude)
            and len(set(exclude)) == len(exclude),
            f"{source}: exclude_columns 형식 오류",
        )
        require(
            isinstance(rename, dict)
            and all(isinstance(c, str) for c in rename.values()),
            f"{source}: column_map 형식 오류",
        )
        require(
            (set(exclude) | set(rename)) <= set(source_columns),
            f"{source}: 덤프에 없는 컬럼을 지정했습니다",
        )
        require(
            not set(exclude) & set(rename),
            f"{source}: 제외와 매핑을 동시에 지정한 컬럼",
        )
        destination_schema = target_schema or config.get("target_schema") or schema
        destination_table = spec.get("target_table", table)
        identifier(destination_schema)
        identifier(destination_table)
        destination = (destination_schema.casefold(), destination_table.casefold())
        require(destination not in destinations, f"중복 타깃 테이블: {destination}")
        destinations.add(destination)
        decode = {}
        columns = []
        selected = []
        for i, column in enumerate(source_columns, 1):
            if column in exclude:
                columns.append(i)
                continue
            target = rename.get(column, column)
            identifier(target)
            selected.append(target)
            function = opts.get("decodeColumns", {}).get(column)
            if function:
                require(
                    function in ("FROM_BASE64", "UNHEX"),
                    f"{source}.{column}: 지원하지 않는 디코딩: {function}",
                )
                columns.append(i)
                decode[target] = f"{function}(@{i})"
            else:
                columns.append(target)
        require(
            selected and len({c.casefold() for c in selected}) == len(selected),
            f"{source}: 적재 컬럼이 없거나 타깃 컬럼이 중복됩니다",
        )
        expected = done.get("tableRows", {}).get(schema, {}).get(table)
        require(
            isinstance(expected, int)
            and not isinstance(expected, bool)
            and expected >= 0,
            f"{source}: 완료 덤프의 tableRows가 필요합니다 (현재 mysqlsh로 다시 덤프하세요)",
        )
        require(files[source] or expected == 0, f"{source}: 데이터 파일이 없습니다")
        extension = table_meta["extension"]
        require(
            all(p.endswith("." + extension) for p in files[source]),
            f"{source}: 덤프 데이터 확장자 불일치",
        )
        charset = opts.get("defaultCharacterSet", meta.get("defaultCharacterSet"))
        require(
            isinstance(charset, str) and charset, f"{source}: 문자셋 메타데이터 없음"
        )
        import_options = {
            key: opts[key]
            for key in (
                "fieldsTerminatedBy",
                "fieldsEnclosedBy",
                "fieldsOptionallyEnclosed",
                "fieldsEscapedBy",
                "linesTerminatedBy",
            )
            if key in opts
        }
        import_options.update(
            schema=destination_schema,
            table=destination_table,
            columns=columns,
            characterSet=charset,
            threads=threads,
            replaceDuplicates=duplicates == "replace",
            sessionInitSql=[
                "SET SESSION time_zone = '+00:00'",
                "SET SESSION unique_checks = 1",
                "SET SESSION foreign_key_checks = 1",
            ],
        )
        if duplicates == "skip":
            require(
                import_options.get("fieldsTerminatedBy", "\t")
                and import_options.get("linesTerminatedBy", "\n"),
                f"{source}: skip에는 필드/행 구분자가 필요합니다",
            )
        if decode:
            import_options["decodeColumns"] = decode
        plan.append(
            {
                "source": source,
                "schema": destination_schema,
                "table": destination_table,
                "selected": selected,
                "excluded": exclude,
                "files": sorted(files[source]),
                "expected": expected,
                "options": import_options,
            }
        )
    return plan


def preflight(plan, session, duplicates, clear_target=False):
    """Validate every destination before the first import; all queries are reads."""
    require(session is not None, "타깃 연결이 필요합니다")
    require(
        session.run_sql("SELECT @@GLOBAL.local_infile").fetch_one()[0] == 1,
        "타깃의 local_infile=ON이 필요합니다",
    )
    if duplicates == "skip":
        # Changing max_error_count needs administrator privileges on newer
        # servers. Respect the existing limit instead. The importer requires
        # transactions >= 4096 bytes; the log check rejects lost diagnostics.
        warning_limit = session.run_sql("SELECT @@GLOBAL.max_error_count").fetch_one()[
            0
        ]
        require(warning_limit > 0, "skip에는 max_error_count > 0이 필요합니다")
        for item in plan:
            if item["expected"] >= warning_limit:
                item["options"]["maxBytesPerTransaction"] = str(
                    max(
                        4096,
                        min(60000, warning_limit - 1) * len(item["options"]["columns"]),
                    )
                )
    for item in plan:
        args = [item["schema"], item["table"]]
        table = session.run_sql(
            "SELECT TABLE_TYPE FROM information_schema.TABLES "
            "WHERE TABLE_SCHEMA=? AND TABLE_NAME=?",
            args,
        ).fetch_one()
        require(table and table[0] == "BASE TABLE", f"기존 타깃 테이블 없음: {args}")
        rows = session.run_sql(
            "SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_DEFAULT, EXTRA, GENERATION_EXPRESSION "
            "FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=? AND TABLE_NAME=? "
            "ORDER BY ORDINAL_POSITION",
            args,
        ).fetch_all()
        columns = {row[0].casefold(): row for row in rows}
        selected = {c.casefold() for c in item["selected"]}
        require(
            selected <= set(columns),
            f"{args}: 타깃에 없는 컬럼: {selected - set(columns)}",
        )
        for name, row in columns.items():
            generated = bool(row[4])
            require(
                not (generated and name in selected),
                f"{args}: 생성 컬럼에 적재할 수 없음: {row[0]}",
            )
            require(
                name in selected
                or generated
                or row[1] == "YES"
                or row[2] is not None
                or "auto_increment" in row[3].lower(),
                f"{args}: 값/기본값이 필요한 타깃 컬럼: {row[0]}",
            )
        qualified = identifier(item["schema"]) + "." + identifier(item["table"])
        if clear_target:
            incoming = session.run_sql(
                "SELECT TABLE_SCHEMA, TABLE_NAME FROM information_schema.KEY_COLUMN_USAGE "
                "WHERE REFERENCED_TABLE_SCHEMA=? AND REFERENCED_TABLE_NAME=? "
                "AND NOT (TABLE_SCHEMA=? AND TABLE_NAME=?) LIMIT 1",
                args + args,
            ).fetch_one()
            require(
                not incoming,
                f"{qualified}: 다른 테이블의 외래 키가 참조하므로 전체 비우기를 거부합니다: {incoming}",
            )
        if duplicates == "error" and not clear_target:
            require(
                session.run_sql(f"SELECT 1 FROM {qualified} LIMIT 1").fetch_one()
                is None,
                f"{qualified}: 데이터가 있습니다. duplicates=skip 또는 replace를 명시하세요",
            )
        elif duplicates != "error" and not clear_target:
            keys = {}
            for name, column in session.run_sql(
                "SELECT INDEX_NAME, COLUMN_NAME FROM information_schema.STATISTICS "
                "WHERE TABLE_SCHEMA=? AND TABLE_NAME=? AND NON_UNIQUE=0",
                args,
            ).fetch_all():
                keys.setdefault(name, []).append(column.casefold() if column else None)
            require(
                any(set(key) <= selected for key in keys.values()),
                f"{qualified}: skip/replace에는 적재 컬럼으로 구성된 PK 또는 UNIQUE 키가 필요합니다",
            )
        print(
            f"{item['source']} -> {qualified}: {item['expected']} rows, "
            f"columns={item['selected']}, exclude={item['excluded']}, duplicates={duplicates}, clear_target={clear_target}"
        )


def confirm_clear(plan, ui):
    ui.say("\n전체 데이터를 비울 타깃 테이블:")
    for item in plan:
        ui.say("  " + identifier(item["schema"]) + "." + identifier(item["table"]))
    ui.say(
        "TRUNCATE는 롤백할 수 없습니다. 적재 실패 시 타깃이 비거나 일부만 적재될 수 있습니다."
    )
    return ui.confirm("위 타깃 테이블의 모든 행을 비우고 적재할까요?")


def execute(plan, session, util, duplicates, clear_target=False):
    print(f"Mapped duplicate policy: {duplicates}", flush=True)
    print(
        f"Mapped import tables: {sum(item['expected'] > 0 for item in plan)}",
        flush=True,
    )
    print(
        "주의: 청크별 커밋입니다. 실패 시 일부 데이터가 남을 수 있으며 자동 이어받기는 없습니다."
    )
    if duplicates == "replace" and not clear_target:
        print(
            "주의: replace는 중복 키 행만 DELETE + INSERT합니다. 다른 기존 행은 남고, 교체된 행의 타깃 전용 값은 초기화될 수 있습니다."
        )
    if clear_target:
        for item in plan:
            qualified = identifier(item["schema"]) + "." + identifier(item["table"])
            session.run_sql(f"TRUNCATE TABLE {qualified}")
            print(f"Cleared: {qualified}", flush=True)
    for item in plan:
        if item["expected"] > 0:
            util.import_table(item["files"], item["options"])
        if duplicates == "error" or clear_target:
            qualified = identifier(item["schema"]) + "." + identifier(item["table"])
            actual = session.run_sql(f"SELECT COUNT(*) FROM {qualified}").fetch_one()[0]
            require(
                actual == item["expected"],
                f"{qualified}: 행 수 불일치 (expected={item['expected']}, actual={actual}); 부분 적재 확인 필요",
            )


def check_log(path, duplicates, diagnostics=None):
    """LOAD DATA LOCAL can report data errors as warnings with exit status zero."""
    ansi = re.compile(r"\x1b\[[0-9;]*m")
    error_pattern = re.compile(r"(LOAD DATA error .*?error (\d+):[^\n]*)")
    summary = re.compile(
        r"^Total rows affected in .*?: Records: (\d+)\s+Deleted: (\d+)"
        r"\s+Skipped: (\d+)\s+Warnings: (\d+)"
    )
    marker = re.compile(r"^Mapped import tables: (\d+)\s*$")
    # The interactive mode can select a policy after connecting. It emits the
    # effective policy before importing, so validate against that policy.
    with Path(path).open(encoding="utf-8") as stream:
        for line in stream:
            policy = re.fullmatch(
                r"Mapped duplicate policy: (error|skip|replace)\s*", line
            )
            if policy:
                duplicates = policy[1]
    errors = 0
    unexpected = []
    with Path(diagnostics or path).open(encoding="utf-8") as stream:
        for line in stream:
            match = error_pattern.search(ansi.sub("", line))
            if match:
                errors += 1
                if (
                    not (duplicates == "skip" and match[2] == "1062")
                    and len(unexpected) < 5
                ):
                    unexpected.append(match[1])
    require(
        not unexpected,
        "적재 경고/오류가 발생했습니다. 부분 적재된 데이터를 확인하세요\n"
        + "\n".join(unexpected),
    )
    expected = None
    summaries = 0
    warnings = 0
    with Path(path).open(encoding="utf-8") as stream:
        for line in stream:
            line = ansi.sub("", line)
            match = marker.match(line)
            if match:
                expected = int(match[1])
            match = summary.match(line)
            if not match:
                continue
            summaries += 1
            skipped, warned = int(match[3]), int(match[4])
            warnings += warned
            require(
                warned == (skipped if duplicates == "skip" else 0),
                "타입 변환/누락 등 적재 경고가 발생했습니다. 부분 적재된 데이터를 확인하세요",
            )
            require(
                duplicates == "skip" or skipped == 0,
                "예상하지 않은 행 건너뛰기가 발생했습니다",
            )
    if expected is not None:
        require(
            summaries == expected,
            "적재 결과 요약이 누락되었습니다. 로그를 확인하세요",
        )
    require(
        warnings == errors,
        "모든 적재 경고를 검증할 수 없습니다. 로그를 확인하세요",
    )


def main(argv):
    if len(argv) == 3 and argv[1] == "--list-mappings":
        for path in mapping_files(argv[2]):
            print(path)
        return
    if len(argv) in (4, 5) and argv[1] == "--check-log":
        check_log(argv[2], argv[3], argv[4] if len(argv) == 5 else None)
        return
    require(
        len(argv) in (7, 8, 9),
        "mysqlsh --py --file mysqlsh_load.py dump mapping schema threads duplicates dry_run [interactive [clear_target]]",
    )
    from mysqlsh import globals as g

    indir, mapping, schema, threads, duplicates, dry_run = argv[1:7]
    require(dry_run in ("true", "false"), "dry_run은 true/false여야 합니다")
    interactive = argv[7] if len(argv) >= 8 else "false"
    clear_target = argv[8] if len(argv) == 9 else "false"
    require(interactive in ("true", "false"), "interactive는 true/false여야 합니다")
    require(clear_target in ("true", "false"), "clear_target은 true/false여야 합니다")
    clear_target = clear_target == "true"
    if interactive == "true" or clear_target:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from lib.mysqlsh_map import Cancelled, TerminalUI, interactive_plan

    if interactive == "true":
        try:
            with TerminalUI() as ui:
                plan, duplicates = interactive_plan(
                    indir,
                    mapping,
                    schema,
                    int(threads),
                    duplicates,
                    dry_run == "true",
                    g.session,
                    ui,
                    clear_target=clear_target,
                )
        except Cancelled:
            print("Mapped load cancelled", flush=True)
            return
    else:
        if not mapping and clear_target:
            root = Path(indir).resolve()
            mapping = {
                "tables": {
                    name: {} for name in dump_index(root, read_json(root / "@.json"))
                }
            }
        plan = build_plan(indir, mapping, schema, int(threads), duplicates)
        preflight(plan, g.session, duplicates, clear_target=clear_target)
        if clear_target and dry_run == "false":
            try:
                with TerminalUI() as ui:
                    if not confirm_clear(plan, ui):
                        raise Cancelled
            except Cancelled:
                print("Mapped load cancelled", flush=True)
                return
    if dry_run == "false":
        execute(plan, g.session, g.util, duplicates, clear_target=clear_target)


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
