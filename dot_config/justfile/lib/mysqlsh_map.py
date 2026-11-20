"""Interactive dump-to-table mapping. Only SELECTs and local mapping-file writes.

The dump DDL is inspected as text, never executed. /dev/tty keeps selection and
confirmation separate from mysqlsh's password input on stdin.
"""

import difflib
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

from .mysqlsh_load import (
    build_plan,
    confirm_clear,
    dump_file,
    dump_index,
    preflight,
    read_json,
    require,
)


class Cancelled(Exception):
    """The operator cancelled before any rows were imported."""


class TerminalUI:
    def __enter__(self):
        try:
            self.reader = open("/dev/tty", encoding="utf-8")
            try:
                self.writer = open("/dev/tty", "w", encoding="utf-8")
            except OSError:
                self.reader.close()
                raise
        except OSError as error:
            raise ValueError(
                "대화형 매핑은 터미널(TTY)이 필요합니다. 터미널에서 실행하거나 매핑 파일을 사용하세요"
            ) from error
        return self

    def __exit__(self, *_args):
        self.reader.close()
        self.writer.close()

    def say(self, message):
        print(message, file=self.writer, flush=True)

    def ask(self, message):
        self.writer.write(message + " ")
        self.writer.flush()
        answer = self.reader.readline()
        if not answer:
            raise Cancelled
        return answer.strip()

    def confirm(self, message):
        return self.ask(message + " [y/N]").lower() in ("y", "yes")

    def choose(self, message, options, default=None, multi=False):
        require(options, f"선택할 항목이 없습니다: {message}")
        # Numeric IDs keep tabs/newlines in identifiers out of the wire format.
        options = sorted(options, key=lambda item: item[0] != default)
        labels = []
        for i, (_key, label) in enumerate(options):
            label = label.replace("\n", r"\n").replace("\t", r"\t")
            labels.append(f"{i}\t{label}")
        args = [
            "fzf",
            "--height=40%",
            "--scheme=default",
            "--no-sort",
            "--delimiter=\t",
            "--with-nth=2..",
            "--prompt="
            + message
            + (" (Tab=multi, Esc=cancel)> " if multi else " (Esc=cancel)> "),
        ]
        if multi:
            args.append("--multi")
        # Inherit the same FZF_* theme and layout as the other recipes.
        result = subprocess.run(
            args,
            input="\n".join(labels) + "\n",
            text=True,
            encoding="utf-8",
            stdout=subprocess.PIPE,
            stderr=self.writer,
            check=False,
        )
        if result.returncode in (1, 130):
            raise Cancelled
        require(result.returncode == 0, f"fzf 선택 실패: {result.returncode}")
        selected = [
            options[int(line.split("\t", 1)[0])][0]
            for line in result.stdout.splitlines()
        ]
        if not selected:
            raise Cancelled
        return selected if multi else selected[0]


def sql_tokens(text):
    """A lexical reader for SHOW CREATE TABLE output, not a general SQL parser."""
    i = 0
    while i < len(text):
        char = text[i]
        if char.isspace():
            i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            require(end >= 0, "닫히지 않은 SQL 주석")
            i = end + 2
        elif char == "#" or (
            text.startswith("--", i) and (i + 2 == len(text) or text[i + 2].isspace())
        ):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end + 1
        elif char in ("`", "'", '"'):
            start = i
            i += 1
            value = ""
            while i < len(text):
                if text[i] == "\\":
                    require(i + 1 < len(text), "닫히지 않은 SQL 문자열")
                    value += text[i : i + 2]
                    i += 2
                elif text[i] == char:
                    if i + 1 < len(text) and text[i + 1] == char:
                        value += char
                        i += 2
                    else:
                        i += 1
                        break
                else:
                    value += text[i]
                    i += 1
            else:
                raise ValueError("닫히지 않은 SQL 인용부호")
            yield ("identifier", value) if char == "`" else ("literal", text[start:i])
        elif char.isalnum() or char in ("_", "$"):
            end = i + 1
            while end < len(text) and (text[end].isalnum() or text[end] in ("_", "$")):
                end += 1
            yield "word", text[i:end]
            i = end
        else:
            yield "punctuation", char
            i += 1


def type_key(value):
    tokens = list(sql_tokens(value))
    parts = []
    previous = None
    previous_text = None
    for kind, text in tokens:
        if kind == "word" and (previous == "word" or previous_text == ")"):
            parts.append(" ")
        parts.append(text.lower() if kind == "word" else text)
        previous = kind
        previous_text = text
    normalized = "".join(parts)
    # Integer display widths are not storage widths and differ across servers.
    return re.sub(
        r"^(tinyint|smallint|mediumint|int|integer|bigint)\(\d+\)", r"\1", normalized
    )


def ddl_columns(text):
    tokens = list(sql_tokens(text))
    start = next(
        (
            i + 2
            for i in range(len(tokens) - 1)
            if tokens[i][0] == tokens[i + 1][0] == "word"
            and tokens[i][1].upper() == "CREATE"
            and tokens[i + 1][1].upper() == "TABLE"
        ),
        None,
    )
    require(start is not None, "CREATE TABLE DDL을 찾을 수 없습니다")
    start = next(i for i in range(start, len(tokens)) if tokens[i][1] == "(")
    groups = [[]]
    depth = 0
    end = start
    for end in range(start + 1, len(tokens)):
        token = tokens[end]
        if token == ("punctuation", "("):
            depth += 1
        elif token == ("punctuation", ")"):
            if depth == 0:
                break
            depth -= 1
        if token == ("punctuation", ",") and depth == 0:
            groups.append([])
        else:
            groups[-1].append(token)
    else:
        raise ValueError("닫히지 않은 CREATE TABLE DDL")
    charset = None
    collation = None
    for i in range(end + 1, len(tokens) - 2):
        if tokens[i][1].upper() == "CHARSET" and tokens[i + 1][1] == "=":
            charset = tokens[i + 2][1]
        if tokens[i][1].upper() == "COLLATE" and tokens[i + 1][1] == "=":
            collation = tokens[i + 2][1]
    attributes = {
        "NOT",
        "NULL",
        "DEFAULT",
        "AUTO_INCREMENT",
        "GENERATED",
        "AS",
        "COMMENT",
        "CHARACTER",
        "COLLATE",
        "COLUMN_FORMAT",
        "STORAGE",
        "SRID",
        "INVISIBLE",
        "VISIBLE",
        "ENGINE_ATTRIBUTE",
        "SECONDARY_ENGINE_ATTRIBUTE",
        "PRIMARY",
        "UNIQUE",
        "REFERENCES",
        "CHECK",
    }
    columns = {}
    for group in groups:
        if not group or group[0][0] != "identifier":
            continue
        depth = 0
        split = len(group)
        for i, (kind, value) in enumerate(group[1:], 1):
            if depth == 0 and kind == "word" and value.upper() in attributes:
                split = i
                break
            if kind == "punctuation":
                depth += (value == "(") - (value == ")")
        require(split > 1, "컬럼 타입이 없는 DDL")
        raw_type = " ".join(value for _kind, value in group[1:split])
        words = []
        depth = 0
        for kind, value in group[split:]:
            if kind == "punctuation":
                depth += (value == "(") - (value == ")")
            if depth == 0:
                words.append(value.upper() if kind == "word" else "")
        nullable = not any(
            words[i : i + 2] == ["NOT", "NULL"] for i in range(len(words) - 1)
        )
        column_charset = (
            charset
            if re.match(
                r"^(?:char|varchar|tinytext|text|mediumtext|longtext|enum|set)\b",
                raw_type,
                re.IGNORECASE,
            )
            else None
        )
        for i in range(split, len(group) - 2):
            if group[i][1].upper() == "CHARACTER" and group[i + 1][1].upper() == "SET":
                column_charset = group[i + 2][1]
        column_collation = (
            collation if column_charset and column_charset == charset else None
        )
        for i in range(split, len(group) - 1):
            if group[i][0] == "word" and group[i][1].upper() == "COLLATE":
                column_collation = group[i + 1][1]
        columns[group[0][1]] = {
            "type": type_key(raw_type),
            "nullable": nullable,
            "charset": column_charset,
            "collation": column_collation,
        }
    return columns


def source_columns(root, base, table_meta):
    columns = {}
    ddl = dump_file(root, base + ".sql")
    if table_meta.get("includesDdl") and ddl.is_file():
        try:
            columns = ddl_columns(ddl.read_text(encoding="utf-8"))
        except (ValueError, StopIteration):
            pass  # Unknown is shown explicitly and never treated as a match.
    return {
        name: columns.get(
            name, {"type": None, "nullable": None, "charset": None, "collation": None}
        )
        for name in table_meta["options"]["columns"]
    }


def target_columns(session, schema, table):
    rows = session.run_sql(
        "SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, EXTRA, "
        "GENERATION_EXPRESSION, CHARACTER_SET_NAME, COLLATION_NAME "
        "FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=? AND TABLE_NAME=? ORDER BY ORDINAL_POSITION",
        [schema, table],
    ).fetch_all()
    require(rows, f"타깃 컬럼을 읽을 수 없습니다: {schema}.{table}")
    return {
        row[0]: {
            "type": type_key(row[1]),
            "nullable": row[2] == "YES",
            "default": row[3],
            "extra": row[4],
            "generated": row[5],
            "charset": row[6],
            "collation": row[7],
        }
        for row in rows
    }


def differences(source, target):
    if source["type"] is None:
        return ["소스 DDL 없음/분석 불가: 타입·NULL 확인 불가"]
    notes = []
    if source["type"] != target["type"]:
        notes.append(f"타입 차이 {source['type']} -> {target['type']}")
    if source["nullable"] != target["nullable"]:
        notes.append("NULL 허용 차이")
    if (
        source["charset"]
        and target["charset"]
        and source["charset"] != target["charset"]
    ):
        notes.append(f"문자셋 차이 {source['charset']} -> {target['charset']}")
    if (
        source.get("collation")
        and target.get("collation")
        and source["collation"] != target["collation"]
    ):
        notes.append(f"콜레이션 차이 {source['collation']} -> {target['collation']}")
    return notes


def ranked_options(name, names):
    return sorted(
        names,
        key=lambda candidate: (
            -difflib.SequenceMatcher(
                None, name.casefold(), candidate.casefold()
            ).ratio(),
            candidate,
        ),
    )


def map_columns(source, target, seed, previous, ui, edit_all=False):
    writable = {name: col for name, col in target.items() if not col["generated"]}
    folded = {name.casefold(): name for name in writable}
    assigned = {}
    used = set()
    # Reserve same-name columns before proposing targets to renamed columns.
    order = sorted(source, key=lambda name: name.casefold() not in folded)
    for name in order:
        old = seed.get("column_map", {}).get(name, name)
        old = folded.get(old.casefold())
        excluded = name in seed.get("exclude_columns", [])
        old_source = previous.get("source", {}).get(name)
        old_targets = previous.get("target", {}).get("columns", {})
        trusted = (
            not edit_all
            and old_source == source[name]
            and (
                (excluded and old_targets == target)
                or (old in writable and old_targets.get(old) == writable[old])
            )
        )
        if trusted and (excluded or old not in used):
            assigned[name] = None if excluded else old
        elif (
            not edit_all
            and not excluded
            and name not in seed.get("column_map", {})
            and name.casefold() in folded
            and folded[name.casefold()] not in used
            and not differences(source[name], writable[folded[name.casefold()]])
        ):
            assigned[name] = folded[name.casefold()]
        else:
            candidates = ranked_options(
                name, [col for col in writable if col not in used]
            )
            options = [
                (
                    col,
                    f"{col} [{writable[col]['type']}] "
                    + "; ".join(differences(source[name], writable[col])),
                )
                for col in candidates
            ]
            options.append((None, "[제외] 이 소스 컬럼을 적재하지 않음"))
            ui.say(
                f"\n확인 필요: {name} [{source[name]['type'] or '소스 타입 확인 불가'}]"
            )
            default = None
            if not excluded:
                if old is not None and old not in used:
                    default = old
                elif candidates:
                    default = candidates[0]
            assigned[name] = ui.choose(
                f"컬럼 {name} 연결/제외", options, default=default
            )
        if assigned[name] is not None:
            used.add(assigned[name])
    return {
        "column_map": {
            src: dst for src, dst in assigned.items() if dst is not None and src != dst
        },
        "exclude_columns": [name for name, dst in assigned.items() if dst is None],
    }


def review(source, target, spec, ui):
    selected = set()
    for name, desc in source.items():
        if name in spec["exclude_columns"]:
            ui.say(f"  {name} [{desc['type'] or '?'}] -> [제외]")
        else:
            destination = spec["column_map"].get(name, name)
            selected.add(destination)
            detail = "; ".join(differences(desc, target[destination])) or "일치"
            ui.say(
                f"  {name} [{desc['type'] or '?'}] -> {destination} [{target[destination]['type']}] ({detail})"
            )
    blocked = []
    if not selected:
        blocked.append("적재할 컬럼이 없습니다")
        ui.say("  [해결 필요] 적재할 컬럼을 하나 이상 연결하세요")
    for name, desc in target.items():
        if name in selected:
            continue
        if desc["generated"]:
            detail = "생성 컬럼: 서버에서 계산"
        elif "auto_increment" in desc["extra"].lower():
            detail = "AUTO_INCREMENT: 서버에서 생성"
        elif desc["default"] is not None:
            detail = f"타깃 기본값 사용: {desc['default']}"
        elif desc["nullable"]:
            detail = "타깃 NULL 사용"
        else:
            detail = "[해결 필요] NOT NULL이며 기본값이 없습니다"
            blocked.append(name)
        ui.say(f"  [소스 연결 없음] -> {name} [{desc['type']}] ({detail})")
    return blocked


def save_mapping(config, path):
    import json

    text = json.dumps(config, ensure_ascii=False, indent=2) + "\n"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(text)


def interactive_plan(
    indir,
    mapping,
    schema,
    threads,
    duplicates,
    dry_run,
    session,
    ui,
    clear_target=False,
):
    root = Path(indir).resolve()
    meta = read_json(root / "@.json")
    require((root / "@.done.json").is_file(), "완료된 덤프(@.done.json)가 필요합니다")
    require(meta.get("tzUtc") is True, "UTC 덤프(tzUtc=true)가 필요합니다")
    index = dump_index(root, meta)
    seed = read_json(Path(mapping)) if mapping else {"tables": {}}
    require(
        isinstance(seed, dict) and isinstance(seed.get("tables"), dict),
        "매핑 tables 형식 오류",
    )
    require(
        isinstance(seed.get("schema_snapshot", {}), dict), "schema_snapshot 형식 오류"
    )
    schemas = [
        row[0]
        for row in session.run_sql(
            "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA "
            "WHERE SCHEMA_NAME NOT IN ('mysql','sys','information_schema','performance_schema') ORDER BY SCHEMA_NAME"
        ).fetch_all()
    ]
    if not schema:
        schema = ui.choose(
            "타깃 스키마",
            [(name, name) for name in schemas],
            default=seed.get("target_schema"),
        )
    tables = [
        row[0]
        for row in session.run_sql(
            "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=? AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME",
            [schema],
        ).fetch_all()
    ]
    require(tables, f"기존 타깃 테이블이 없습니다: {schema}")
    saved = seed["tables"]
    if (
        saved
        and set(saved) <= set(index)
        and ui.choose(
            "소스 테이블 선택",
            [("saved", "저장된 테이블 선택 사용"), ("select", "덤프에서 다시 선택")],
            default="saved",
        )
        == "saved"
    ):
        sources = list(saved)
    else:
        sources = ui.choose(
            "소스 테이블 (선택 순서로 적재)",
            [(name, name) for name in index],
            multi=True,
        )
    config = {"tables": {}, "schema_snapshot": {}, "target_schema": schema}
    used_tables = set()
    for name in sources:
        _source_schema, source_table, base = index[name]
        table_meta = read_json(dump_file(root, base + ".json"))
        require(table_meta.get("includesData") is True, f"{name}: 데이터가 없는 덤프")
        source = source_columns(root, base, table_meta)
        old = saved.get(name, {})
        require(isinstance(old, dict), f"{name}: 매핑 형식 오류")
        choices = ranked_options(
            old.get("target_table", source_table),
            [t for t in tables if t not in used_tables],
        )
        table = ui.choose(
            f"{name}의 타깃 테이블",
            [(t, t) for t in choices] + [(None, "[이 소스 테이블 제외]")],
            default=old.get("target_table", source_table),
        )
        if table is None:
            continue
        target = target_columns(session, schema, table)
        previous = seed.get("schema_snapshot", {}).get(name, {})
        require(
            isinstance(previous, dict)
            and isinstance(previous.get("source", {}), dict)
            and isinstance(previous.get("target", {}), dict)
            and isinstance(previous.get("target", {}).get("columns", {}), dict),
            f"{name}: schema_snapshot 형식 오류",
        )
        if (
            previous.get("target", {}).get("schema") != schema
            or previous.get("target", {}).get("table") != table
        ):
            previous = {}
        edit_all = False
        while True:
            spec = map_columns(source, target, old, previous, ui, edit_all)
            ui.say(f"\n매핑 검토: {name} -> {schema}.{table}")
            blocked = review(source, target, spec, ui)
            actions = [
                ("edit", "컬럼 연결/제외 다시 선택"),
                ("skip", "이 테이블 제외"),
                ("cancel", "전체 취소"),
            ]
            if not blocked:
                actions.insert(0, ("accept", "이 매핑 사용"))
            action = ui.choose(
                "매핑 검토", actions, default="edit" if blocked else "accept"
            )
            if action == "cancel":
                raise Cancelled
            if action == "skip":
                break
            if action == "accept":
                spec["target_table"] = table
                config["tables"][name] = spec
                config["schema_snapshot"][name] = {
                    "source": source,
                    "target": {"schema": schema, "table": table, "columns": target},
                }
                used_tables.add(table)
                break
            old = spec
            edit_all = True
    if not config["tables"]:
        raise Cancelled
    duplicates = ui.choose(
        "기존 행 처리",
        [
            ("error", "error: 빈 타깃에 적재 (clear_target=true면 먼저 비움)"),
            ("skip", "skip: 중복 키 행 유지, 신규 행 추가"),
            (
                "replace",
                "replace: 중복 키 행만 교체 (나머지 기존 행은 유지)",
            ),
        ],
        default=duplicates,
    )
    plan = build_plan(root, config, schema, threads, duplicates)
    preflight(plan, session, duplicates, clear_target=clear_target)
    ui.say(
        f"\n사전 검사 완료: {len(plan)}개 테이블, {sum(item['expected'] for item in plan)}행, duplicates={duplicates}, clear_target={clear_target}"
    )
    default_path = root / (
        "mapping_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f") + ".json"
    )
    save = ui.choose(
        "매핑 저장",
        [
            ("default", f"저장: {default_path}"),
            ("path", "다른 경로에 저장"),
            ("none", "저장하지 않음"),
        ],
        default="default",
    )
    if save != "none":
        while True:
            path = (
                default_path
                if save == "default"
                else Path(ui.ask("저장 경로 (빈 입력=취소):")).expanduser()
            )
            if str(path) == ".":
                raise Cancelled
            try:
                save_mapping(config, path)
                ui.say(f"매핑 저장 완료: {path}")
                break
            except FileExistsError:
                ui.say(f"파일이 이미 있습니다. 다른 경로를 선택하세요: {path}")
                save = "path"
    if not dry_run:
        accepted = (
            confirm_clear(plan, ui)
            if clear_target
            else ui.confirm("위 매핑으로 데이터를 적재할까요?")
        )
        if not accepted:
            raise Cancelled
    return plan, duplicates
