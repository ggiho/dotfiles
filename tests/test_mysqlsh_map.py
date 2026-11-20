import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from lib import mysqlsh_map as mapper


class ScriptedUI:
    def __init__(self, answers=None, confirmations=True, paths=()):
        self.answers = answers or {}
        self.confirmations = confirmations
        self.paths = iter(paths)
        self.messages = []
        self.calls = []

    def say(self, text):
        self.messages.append(text)

    def choose(self, message, options, default=None, multi=False):
        self.calls.append((message, [key for key, _label in options]))
        if message in self.answers:
            value = self.answers[message]
            if isinstance(value, list) and not multi:
                value = value.pop(0)
        elif multi:
            value = [options[0][0]]
        elif message == "매핑 저장":
            value = "none"
        else:
            value = default if default in [key for key, _ in options] else options[0][0]
        for key in value if multi else [value]:
            if key not in [key for key, _ in options]:
                raise AssertionError(f"Invalid choice {key!r} for {message}: {options}")
        return value

    def ask(self, message):
        self.messages.append(message)
        return str(next(self.paths))

    def confirm(self, message):
        self.messages.append(message)
        return self.confirmations


class TerminalUIStyleTests(unittest.TestCase):
    def setUp(self):
        self.ui = mapper.TerminalUI()
        self.ui.writer = io.StringIO()
        command = patch(
            "lib.mysqlsh_map.subprocess.run",
            return_value=Mock(returncode=0, stdout="0\t표시 이름\n"),
        )
        self.run = command.start()
        self.addCleanup(command.stop)

    def test_preserves_shared_fzf_theme_environment(self):
        with tempfile.TemporaryDirectory() as temp:
            theme_file = Path(temp) / "fzf.opts"
            theme_file.write_text("--border=rounded\n")
            theme = "--style=full --layout=reverse --marker=✓ --color=prompt:#cba6f7"
            with patch.dict(
                os.environ,
                {
                    "FZF_DEFAULT_OPTS": theme,
                    "FZF_DEFAULT_OPTS_FILE": str(theme_file),
                },
            ):
                self.assertEqual(
                    self.ui.choose("선택", [("value", "표시 이름")]), "value"
                )
                effective_env = self.run.call_args.kwargs.get("env", os.environ)
                self.assertEqual(effective_env.get("FZF_DEFAULT_OPTS"), theme)
                self.assertEqual(
                    effective_env.get("FZF_DEFAULT_OPTS_FILE"), str(theme_file)
                )

    def test_matches_existing_recipe_picker_options(self):
        self.ui.choose("선택", [("value", "표시 이름")], multi=True)
        args = self.run.call_args.args[0]
        self.assertIn("--height=40%", args)
        self.assertIn("--scheme=default", args)
        self.assertIn("--multi", args)
        self.assertIn("--with-nth=2..", args)


class DDLTests(unittest.TestCase):
    def test_reads_types_nullability_and_charset_from_dump_ddl(self):
        ddl = r"""-- dump header
/*!40101 SET SQL_MODE=''; */
CREATE TABLE `people` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user``name` varchar(50) COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'NOT NULL, )',
  `kind` enum('A, B','NOT NULL','it\'s') NOT NULL DEFAULT 'A, B',
  `amount` decimal(10,2) unsigned DEFAULT NULL,
  `latin` text CHARACTER SET latin1 COLLATE latin1_bin,
  `derived` varchar(50) GENERATED ALWAYS AS (concat(`id`, ',', `user``name`)) STORED,
  PRIMARY KEY (`id`), KEY `idx` (`user``name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"""
        columns = mapper.ddl_columns(ddl)
        self.assertEqual(columns["id"]["type"], "bigint unsigned")
        self.assertFalse(columns["id"]["nullable"])
        self.assertTrue(columns["user`name"]["nullable"])
        self.assertEqual(columns["user`name"]["collation"], "utf8mb4_bin")
        self.assertEqual(columns["kind"]["type"], r"enum('A, B','NOT NULL','it\'s')")
        self.assertEqual(columns["amount"]["type"], "decimal(10,2) unsigned")
        self.assertEqual(columns["latin"]["charset"], "latin1")
        self.assertNotIn("idx", columns)

    def test_literal_case_and_spacing_remain_significant(self):
        self.assertNotEqual(
            mapper.type_key("enum('A, B')"), mapper.type_key("enum('A,B')")
        )
        self.assertNotEqual(mapper.type_key("enum('A')"), mapper.type_key("enum('a')"))
        self.assertEqual(
            mapper.type_key("INT(11) UNSIGNED"), mapper.type_key("int unsigned")
        )

    def test_incomplete_sql_is_not_interpreted_as_a_match(self):
        for ddl in (
            "CREATE TABLE `t` (`a` varchar(50)",
            "CREATE TABLE `t` (`a` enum('unterminated))",
        ):
            with self.subTest(ddl=ddl), self.assertRaises(ValueError):
                mapper.ddl_columns(ddl)


class InteractiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.write(
            "@.json",
            {
                "schemas": ["source"],
                "basenames": {"source": "source"},
                "tzUtc": True,
                "defaultCharacterSet": "utf8mb4",
            },
        )
        self.write(
            "@.done.json",
            {
                "tableRows": {"source": {"people": 2}},
                "chunkFileBytes": {"source@people@@0.tsv.zst": 20},
            },
        )
        self.write(
            "source.json",
            {"tables": ["people"], "basenames": {"people": "source@people"}},
        )
        self.table_meta = {
            "includesData": True,
            "includesDdl": True,
            "extension": "tsv.zst",
            "options": {
                "columns": ["id", "user_name", "debug_text"],
                "fieldsTerminatedBy": "\t",
                "linesTerminatedBy": "\n",
                "fieldsEscapedBy": "\\",
            },
        }
        self.write("source@people.json", self.table_meta)
        self.ddl = "CREATE TABLE `people` (`id` bigint NOT NULL, `user_name` varchar(50), `debug_text` text, PRIMARY KEY (`id`)) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"
        (self.root / "source@people.sql").write_text(self.ddl)
        (self.root / "source@people@@0.tsv.zst").write_bytes(b"fake-data")
        self.columns = [
            ["id", "bigint", "NO", None, "", "", None, None],
            [
                "display_name",
                "varchar(80)",
                "NO",
                None,
                "",
                "",
                "utf8mb4",
                "utf8mb4_0900_ai_ci",
            ],
            ["extra", "int", "NO", "42", "", "", None, None],
        ]
        self.nonempty = False
        self.session = Mock()
        self.session.run_sql.side_effect = self.query

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def query(self, sql, args=None):
        self.assertTrue(sql.startswith("SELECT "), sql)
        result = Mock()
        if "information_schema.SCHEMATA" in sql:
            result.fetch_all.return_value = [["destination"]]
        elif sql.startswith("SELECT TABLE_NAME"):
            result.fetch_all.return_value = [["users"]]
        elif sql.startswith("SELECT TABLE_TYPE"):
            result.fetch_one.return_value = ["BASE TABLE"]
        elif "COLUMN_TYPE" in sql:
            result.fetch_all.return_value = self.columns
        elif "information_schema.COLUMNS" in sql:
            result.fetch_all.return_value = [
                [row[0], row[2], row[3], row[4], row[5]] for row in self.columns
            ]
        elif "STATISTICS" in sql:
            result.fetch_all.return_value = [["PRIMARY", "id"]]
        elif "local_infile" in sql:
            result.fetch_one.return_value = [1]
        elif "max_error_count" in sql:
            result.fetch_one.return_value = [1024]
        elif sql.startswith("SELECT 1 FROM"):
            result.fetch_one.return_value = [1] if self.nonempty else None
        else:
            self.fail(f"Unexpected query: {sql} {args}")
        return result

    def ui(self, answers=None, **kwargs):
        base = {
            "컬럼 user_name 연결/제외": "display_name",
            "컬럼 debug_text 연결/제외": None,
        }
        base.update(answers or {})
        return ScriptedUI(base, **kwargs)

    def run_plan(self, ui, mapping="", dry_run=False, duplicates="error"):
        with contextlib.redirect_stdout(io.StringIO()):
            return mapper.interactive_plan(
                self.root, mapping, "", 4, duplicates, dry_run, self.session, ui
            )

    def test_selects_table_renames_and_excludes_columns(self):
        ui = self.ui()
        plan, mode = self.run_plan(ui)
        self.assertEqual(mode, "error")
        self.assertEqual(plan[0]["schema"], "destination")
        self.assertEqual(plan[0]["table"], "users")
        self.assertEqual(plan[0]["options"]["columns"], ["id", "display_name", 3])
        self.assertFalse(any(message.startswith("컬럼 id") for message, _ in ui.calls))
        self.assertIn("타입 차이 varchar(50) -> varchar(80)", "\n".join(ui.messages))
        self.assertIn("NULL 허용 차이", "\n".join(ui.messages))
        self.assertIn("타깃 기본값 사용: 42", "\n".join(ui.messages))

    def test_cancelled_review_has_no_file_or_data_writes(self):
        ui = self.ui({"매핑 검토": "cancel"})
        with self.assertRaises(mapper.Cancelled):
            self.run_plan(ui)
        self.assertFalse(list(self.root.glob("mapping_*.json")))

    def test_final_confirmation_defaults_to_no_import(self):
        with self.assertRaises(mapper.Cancelled):
            self.run_plan(self.ui(confirmations=False))

    def test_dry_run_never_asks_to_import(self):
        ui = self.ui(confirmations=False)
        self.run_plan(ui, dry_run=True)
        self.assertFalse(any("적재할까요" in message for message in ui.messages))

    def test_skip_and_replace_are_explicitly_selected(self):
        self.nonempty = True
        for mode in ("skip", "replace"):
            with self.subTest(mode=mode):
                _plan, selected = self.run_plan(self.ui({"기존 행 처리": mode}))
                self.assertEqual(selected, mode)

    def test_required_unmapped_column_blocks_acceptance(self):
        self.columns.append(["required", "int", "NO", None, "", "", None, None])
        ui = self.ui({"매핑 검토": "cancel"})
        with self.assertRaises(mapper.Cancelled):
            self.run_plan(ui)
        choices = next(
            options for message, options in ui.calls if message == "매핑 검토"
        )
        self.assertNotIn("accept", choices)
        self.assertIn("NOT NULL이며 기본값이 없습니다", "\n".join(ui.messages))

    def test_editing_can_connect_a_required_target_column(self):
        self.columns.append(["required", "int", "NO", None, "", "", None, None])
        ui = self.ui(
            {
                "매핑 검토": ["edit", "accept"],
                "컬럼 debug_text 연결/제외": [None, "required"],
            }
        )
        plan, _ = self.run_plan(ui)
        self.assertEqual(
            plan[0]["options"]["columns"], ["id", "display_name", "required"]
        )

    def test_excluding_the_source_table_cancels_without_import(self):
        with self.assertRaises(mapper.Cancelled):
            self.run_plan(self.ui({"source.people의 타깃 테이블": None}))

    def save_first_mapping(self):
        path = self.root / "saved.json"
        self.run_plan(self.ui({"매핑 저장": "path"}, paths=[path]), dry_run=True)
        self.assertTrue(path.is_file())
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        return path

    def test_saved_mapping_reuses_choices_but_rechecks_changed_types(self):
        path = self.save_first_mapping()
        ui = self.ui()
        self.run_plan(ui, mapping=str(path))
        self.assertFalse(any(message.startswith("컬럼 ") for message, _ in ui.calls))
        self.columns[1][1] = "varchar(90)"
        ui = self.ui()
        self.run_plan(ui, mapping=str(path))
        prompts = [message for message, _ in ui.calls if message.startswith("컬럼 ")]
        self.assertIn("컬럼 user_name 연결/제외", prompts)
        self.assertNotIn("컬럼 id 연결/제외", prompts)

    def test_saved_mapping_can_load_with_its_target_schema(self):
        path = self.save_first_mapping()
        plan = mapper.build_plan(self.root, path, "", 4, "error")
        self.assertEqual(plan[0]["schema"], "destination")

    def test_changed_source_ddl_is_reviewed_again(self):
        path = self.save_first_mapping()
        (self.root / "source@people.sql").write_text(
            self.ddl.replace("varchar(50)", "varchar(70)")
        )
        ui = self.ui()
        self.run_plan(ui, mapping=str(path))
        self.assertTrue(
            any(message == "컬럼 user_name 연결/제외" for message, _ in ui.calls)
        )

    def test_existing_mapping_is_not_overwritten(self):
        path = self.root / "existing.json"
        path.write_text("keep-me")
        new_path = self.root / "new.json"
        ui = self.ui({"매핑 저장": "path"}, paths=[path, new_path])
        self.run_plan(ui, dry_run=True)
        self.assertEqual(path.read_text(), "keep-me")
        self.assertTrue(new_path.is_file())

    def test_no_ddl_is_shown_as_unknown_and_requires_selection(self):
        (self.root / "source@people.sql").unlink()
        ui = self.ui()
        self.run_plan(ui)
        self.assertTrue(any(message.startswith("컬럼 id") for message, _ in ui.calls))
        self.assertIn("타입·NULL 확인 불가", "\n".join(ui.messages))

    def test_generated_target_is_not_offered_for_mapping(self):
        self.columns.append(
            ["derived", "int", "YES", None, "STORED GENERATED", "id * 2", None, None]
        )
        ui = self.ui()
        self.run_plan(ui)
        column_choices = [
            options for message, options in ui.calls if message.startswith("컬럼 ")
        ]
        self.assertFalse(any("derived" in options for options in column_choices))
        self.assertIn("서버에서 계산", "\n".join(ui.messages))


if __name__ == "__main__":
    unittest.main()
