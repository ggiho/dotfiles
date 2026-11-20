import contextlib
import copy
import io
import json
import tempfile
import tracemalloc
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from lib import mysqlsh_load as loader


class MappingDiscoveryTests(unittest.TestCase):
    def test_discovers_only_mapping_jsons_with_bounded_search_and_no_duplicates(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            dump = root / "dump"
            dump.mkdir()
            other = root / "configs"
            other.mkdir()
            deep = other / "deep"
            deep.mkdir()
            expected = {
                dump / "mapping_saved.json",
                root / "custom name.json",
                other / "custom.json",
            }
            for path in [*expected, deep / "not-searched.json"]:
                path.write_text('{"tables":{"source.people":{}}}')
            for name, text in {
                "@.json": '{"tables":{"pretend":{}}}',
                "schema.json": '{"tables":["people"]}',
                "empty.json": '{"tables":{}}',
                "other.json": '{"tables":{"people":{"ddl":"not mapping"}}}',
                "broken.json": "{broken",
                "duplicate.json": '{"tables":{},"tables":{"s.t":{}}}',
            }.items():
                (dump / name).write_text(text)
            found = loader.mapping_files(dump, root)
            self.assertEqual(set(found), expected)
            self.assertEqual(len(found), len(expected))


class MappingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.mapping = self.root / "mapping.json"
        self.meta = {
            "schemas": ["source"],
            "basenames": {"source": "source"},
            "tzUtc": True,
            "defaultCharacterSet": "utf8mb4",
        }
        self.done = {
            "tableRows": {"source": {"people": 2}},
            "chunkFileBytes": {"source@people@@0.tsv.zst": 20},
        }
        self.table_meta = {
            "includesData": True,
            "extension": "tsv.zst",
            "options": {
                "columns": ["id", "user_name", "secret", "payload", "created_at"],
                "decodeColumns": {"payload": "FROM_BASE64"},
                "fieldsTerminatedBy": "\t",
                "linesTerminatedBy": "\n",
                "fieldsEscapedBy": "\\",
            },
        }
        self.spec = {
            "exclude_columns": ["secret"],
            "column_map": {"user_name": "display_name"},
        }
        (self.root / "source@people@@0.tsv.zst").write_bytes(b"fake-data")
        self.write(
            "source.json",
            {"tables": ["people"], "basenames": {"people": "source@people"}},
        )
        self.columns = [
            ["id", "NO", None, "", ""],
            ["display_name", "YES", None, "", ""],
            ["payload", "YES", None, "", ""],
            ["created_at", "YES", None, "", ""],
            ["extra", "NO", "42", "", ""],
        ]
        self.present = None
        self.table_type = ["BASE TABLE"]
        self.local_infile = 1
        self.warning_limit = 1024
        self.keys = [["PRIMARY", "id"]]
        self.incoming = None
        self.session = Mock()
        self.session.run_sql.side_effect = self.query

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def plan(self, duplicates="error", target_schema="destination", tables=None):
        self.write("@.json", self.meta)
        self.write("@.done.json", self.done)
        self.write("source@people.json", self.table_meta)
        self.write("mapping.json", {"tables": tables or {"source.people": self.spec}})
        return loader.build_plan(self.root, self.mapping, target_schema, 4, duplicates)

    def query(self, sql, args=None):
        result = Mock()
        if "@@GLOBAL.local_infile" in sql:
            result.fetch_one.return_value = [self.local_infile]
        elif "@@GLOBAL.max_error_count" in sql:
            result.fetch_one.return_value = [self.warning_limit]
        elif "information_schema.TABLES" in sql:
            result.fetch_one.return_value = self.table_type
        elif "information_schema.COLUMNS" in sql:
            result.fetch_all.return_value = self.columns
        elif "information_schema.STATISTICS" in sql:
            result.fetch_all.return_value = self.keys
        elif "information_schema.KEY_COLUMN_USAGE" in sql:
            result.fetch_one.return_value = self.incoming
        elif sql.startswith("TRUNCATE TABLE"):
            result.fetch_one.return_value = None
        elif sql.startswith("SELECT 1 FROM"):
            result.fetch_one.return_value = self.present
        elif sql.startswith("SELECT COUNT(*)"):
            result.fetch_one.return_value = [2]
        else:
            self.fail(f"Unexpected query: {sql} {args}")
        return result

    def preflight(self, plan, duplicates="error"):
        with contextlib.redirect_stdout(io.StringIO()):
            loader.preflight(plan, self.session, duplicates)

    def test_mapping_preserves_file_order_and_decoding(self):
        (item,) = self.plan()
        self.assertEqual(
            item["options"]["columns"], ["id", "display_name", 3, 4, "created_at"]
        )
        self.assertEqual(
            item["options"]["decodeColumns"], {"payload": "FROM_BASE64(@4)"}
        )
        self.assertEqual(item["options"]["characterSet"], "utf8mb4")
        self.assertEqual(
            item["options"]["sessionInitSql"],
            [
                "SET SESSION time_zone = '+00:00'",
                "SET SESSION unique_checks = 1",
                "SET SESSION foreign_key_checks = 1",
            ],
        )
        self.assertEqual(item["files"], [str(self.root / "source@people@@0.tsv.zst")])
        self.assertEqual(item["expected"], 2)

    def test_table_and_binary_column_can_be_renamed(self):
        self.spec["target_table"] = "renamed"
        self.spec["column_map"]["payload"] = "new_blob"
        (item,) = self.plan()
        self.assertEqual(item["table"], "renamed")
        self.assertEqual(
            item["options"]["decodeColumns"], {"new_blob": "FROM_BASE64(@4)"}
        )

    def test_excluded_binary_is_not_decoded(self):
        self.spec["exclude_columns"].append("payload")
        self.assertNotIn("decodeColumns", self.plan()[0]["options"])

    def test_unmapped_columns_are_not_silently_excluded(self):
        self.spec["exclude_columns"] = []
        with self.assertRaisesRegex(ValueError, "타깃에 없는 컬럼"):
            self.preflight(self.plan())

    def test_unknown_and_conflicting_column_rules_fail(self):
        for change in (
            {"exclude_columns": ["typo"]},
            {"column_map": {"typo": "name"}},
            {"column_map": {"secret": "display_name"}},
            {"column_map": {"user_name": "ID"}},
            {"column_map": {"user_name": ""}},
            {"ignore_typo": []},
        ):
            with self.subTest(change=change):
                original = dict(self.spec)
                self.spec.update(change)
                with self.assertRaises(ValueError):
                    self.plan()
                self.spec = original

    def test_complete_utc_data_dump_required(self):
        self.meta["tzUtc"] = False
        with self.assertRaisesRegex(ValueError, "UTC"):
            self.plan()
        self.meta["tzUtc"] = True
        self.table_meta["includesData"] = False
        with self.assertRaisesRegex(ValueError, "데이터가 없는"):
            self.plan()

    def test_expected_row_count_and_manifest_required(self):
        del self.done["tableRows"]
        with self.assertRaisesRegex(ValueError, "tableRows"):
            self.plan()

    def test_missing_chunk_fails_before_writes(self):
        (self.root / "source@people@@0.tsv.zst").unlink()
        with self.assertRaisesRegex(ValueError, "청크 없음"):
            self.plan()

    def test_similar_table_names_do_not_mix_data_files(self):
        self.write(
            "source.json",
            {
                "tables": ["people", "people.archived"],
                "basenames": {
                    "people": "source@people",
                    "people.archived": "source@people.archived",
                },
            },
        )
        name = "source@people.archived@@0.tsv.zst"
        (self.root / name).write_bytes(b"other-table")
        self.done["chunkFileBytes"][name] = 11
        self.assertEqual(len(self.plan()[0]["files"]), 1)

    def test_path_traversal_in_manifest_rejected(self):
        self.done["chunkFileBytes"]["../outside"] = 1
        with self.assertRaisesRegex(ValueError, "파일명"):
            self.plan()

    def test_empty_table_without_data_files(self):
        self.done["tableRows"]["source"]["people"] = 0
        self.done["chunkFileBytes"] = {}
        self.assertEqual(self.plan()[0]["files"], [])

    def test_skip_and_replace_use_existing_keys(self):
        self.present = [1]
        for mode in ("skip", "replace"):
            with self.subTest(mode=mode):
                plan = self.plan(mode)
                self.preflight(plan, mode)
                self.assertEqual(
                    plan[0]["options"]["replaceDuplicates"], mode == "replace"
                )

    def test_nonempty_table_rejected_by_default(self):
        self.present = [1]
        with self.assertRaisesRegex(ValueError, "데이터가 있습니다"):
            self.preflight(self.plan())

    def test_required_target_column_rejected(self):
        self.columns.append(["required", "NO", None, "", ""])
        with self.assertRaisesRegex(ValueError, "값/기본값"):
            self.preflight(self.plan())

    def test_generated_and_auto_increment_columns_can_be_omitted(self):
        self.columns.extend(
            [
                ["derived", "NO", None, "STORED GENERATED", "id * 2"],
                ["sequence", "NO", None, "auto_increment", ""],
            ]
        )
        self.preflight(self.plan())

    def test_generated_target_cannot_receive_values(self):
        self.columns[1][4] = "CONCAT(id)"
        with self.assertRaisesRegex(ValueError, "생성 컬럼"):
            self.preflight(self.plan())

    def test_missing_table_or_view_rejected(self):
        for value in (None, ["VIEW"]):
            with self.subTest(value=value):
                self.table_type = value
                with self.assertRaisesRegex(ValueError, "기존 타깃"):
                    self.preflight(self.plan())

    def test_local_infile_must_be_enabled(self):
        self.local_infile = 0
        with self.assertRaisesRegex(ValueError, "local_infile"):
            self.preflight(self.plan())

    def test_skip_requires_a_fully_mapped_unique_key(self):
        self.keys = [["unique_extra", "extra"]]
        with self.assertRaisesRegex(ValueError, "UNIQUE"):
            self.preflight(self.plan("skip"), "skip")

    def test_skip_respects_existing_warning_limit_without_admin_setting(self):
        self.warning_limit = 2
        plan = self.plan("skip")
        self.preflight(plan, "skip")
        self.assertEqual(plan[0]["options"]["maxBytesPerTransaction"], "4096")
        self.assertFalse(
            any(
                "max_error_count" in sql for sql in plan[0]["options"]["sessionInitSql"]
            )
        )
        self.warning_limit = 0
        with self.assertRaisesRegex(ValueError, "max_error_count"):
            self.preflight(plan, "skip")

    def test_identifiers_are_quoted_and_metadata_parameters_bound(self):
        plan = self.plan(target_schema="dest`name")
        self.preflight(plan)
        queries = self.session.run_sql.call_args_list
        self.assertTrue(
            any(
                call.args == ("SELECT 1 FROM `dest``name`.`people` LIMIT 1",)
                for call in queries
            )
        )
        self.assertTrue(
            any(
                len(call.args) == 2 and call.args[1] == ["dest`name", "people"]
                for call in queries
            )
        )

    def test_execute_checks_rows_and_does_not_issue_ddl(self):
        plan = self.plan()
        util = Mock()
        with contextlib.redirect_stdout(io.StringIO()):
            loader.execute(plan, self.session, util, "error")
        util.import_table.assert_called_once_with(plan[0]["files"], plan[0]["options"])
        self.assertTrue(
            all(
                call.args[0].startswith("SELECT ")
                for call in self.session.run_sql.call_args_list
            )
        )
        self.session.run_sql.return_value.fetch_one.return_value = [1]
        self.session.run_sql.side_effect = None
        with (
            contextlib.redirect_stdout(io.StringIO()),
            self.assertRaisesRegex(ValueError, "행 수 불일치"),
        ):
            loader.execute(plan, self.session, util, "error")

    def test_duplicate_json_key_rejected(self):
        self.mapping.write_text('{"tables":{},"tables":{}}')
        with self.assertRaisesRegex(ValueError, "중복 JSON"):
            loader.read_json(self.mapping)

    def test_clear_preflight_allows_existing_rows_and_rejects_incoming_foreign_keys(
        self,
    ):
        self.present = [1]
        plan = self.plan()
        with contextlib.redirect_stdout(io.StringIO()):
            loader.preflight(plan, self.session, "error", clear_target=True)
        self.incoming = ["destination", "child"]
        with self.assertRaisesRegex(ValueError, "외래 키"):
            loader.preflight(plan, self.session, "error", clear_target=True)
        self.assertFalse(
            any(
                call.args[0].startswith("TRUNCATE")
                for call in self.session.run_sql.call_args_list
            )
        )

    def test_clear_does_not_require_a_mapped_unique_key_for_preexisting_rows(self):
        self.keys = []
        plan = self.plan("replace")
        with contextlib.redirect_stdout(io.StringIO()):
            loader.preflight(plan, self.session, "replace", clear_target=True)

    def test_clear_truncates_only_selected_tables_before_any_import(self):
        first = self.plan()[0]
        second = copy.deepcopy(first)
        second["table"] = second["options"]["table"] = "second"
        events = []

        def query(sql, args=None):
            if sql.startswith("TRUNCATE TABLE"):
                events.append(sql)
            return self.query(sql, args)

        self.session.run_sql.side_effect = query
        util = Mock()
        util.import_table.side_effect = lambda files, opts: events.append(
            "import " + opts["table"]
        )
        with contextlib.redirect_stdout(io.StringIO()):
            loader.execute(
                [first, second], self.session, util, "replace", clear_target=True
            )
        self.assertEqual(
            events,
            [
                "TRUNCATE TABLE `destination`.`people`",
                "TRUNCATE TABLE `destination`.`second`",
                "import people",
                "import second",
            ],
        )

    def test_clear_empty_source_still_empties_target(self):
        self.done["tableRows"]["source"]["people"] = 0
        plan = self.plan()
        self.session.run_sql.side_effect = None
        self.session.run_sql.return_value.fetch_one.return_value = [0]
        util = Mock()
        with contextlib.redirect_stdout(io.StringIO()):
            loader.execute(plan, self.session, util, "error", clear_target=True)
        util.import_table.assert_not_called()
        self.session.run_sql.assert_any_call("TRUNCATE TABLE `destination`.`people`")

    def test_clear_main_dry_run_and_cancellation_never_truncate(self):
        self.plan()  # write a complete mapping fixture
        self.present = [1]
        for dry_run in ("true", "false"):
            with self.subTest(dry_run=dry_run):
                self.session.run_sql.reset_mock()
                util = Mock()
                ui = Mock()
                ui.confirm.return_value = False
                terminal = Mock()
                terminal.__enter__ = Mock(return_value=ui)
                terminal.__exit__ = Mock(return_value=False)
                globals_ = SimpleNamespace(session=self.session, util=util)
                with (
                    patch.dict(
                        "sys.modules", {"mysqlsh": SimpleNamespace(globals=globals_)}
                    ),
                    patch("lib.mysqlsh_map.TerminalUI", return_value=terminal),
                    contextlib.redirect_stdout(io.StringIO()),
                ):
                    loader.main(
                        [
                            "helper",
                            str(self.root),
                            str(self.mapping),
                            "destination",
                            "4",
                            "error",
                            dry_run,
                            "false",
                            "true",
                        ]
                    )
                util.import_table.assert_not_called()
                self.assertFalse(
                    any(
                        call.args[0].startswith("TRUNCATE")
                        for call in self.session.run_sql.call_args_list
                    )
                )
                if dry_run == "true":
                    ui.confirm.assert_not_called()

    def test_clear_without_mapping_builds_same_name_table_plan(self):
        self.plan()
        self.columns[1][0] = "user_name"
        self.columns.append(["secret", "YES", None, "", ""])
        self.present = [1]
        util = Mock()
        ui = Mock()
        ui.confirm.return_value = True
        terminal = Mock()
        terminal.__enter__ = Mock(return_value=ui)
        terminal.__exit__ = Mock(return_value=False)
        globals_ = SimpleNamespace(session=self.session, util=util)
        with (
            patch.dict("sys.modules", {"mysqlsh": SimpleNamespace(globals=globals_)}),
            patch("lib.mysqlsh_map.TerminalUI", return_value=terminal),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            loader.main(
                [
                    "helper",
                    str(self.root),
                    "",
                    "destination",
                    "4",
                    "error",
                    "false",
                    "false",
                    "true",
                ]
            )
        self.session.run_sql.assert_any_call("TRUNCATE TABLE `destination`.`people`")
        self.assertEqual(util.import_table.call_args.args[1]["table"], "people")
        self.assertEqual(util.import_table.call_args.args[1]["schema"], "destination")
        ui.confirm.assert_called_once()

    def test_clear_preflight_failure_does_not_open_confirmation_or_execute(self):
        self.plan()
        self.incoming = ["destination", "child"]
        globals_ = SimpleNamespace(session=self.session, util=Mock())
        with (
            patch.dict("sys.modules", {"mysqlsh": SimpleNamespace(globals=globals_)}),
            patch("lib.mysqlsh_map.TerminalUI") as terminal,
            contextlib.redirect_stdout(io.StringIO()),
            self.assertRaisesRegex(ValueError, "외래 키"),
        ):
            loader.main(
                [
                    "helper",
                    str(self.root),
                    str(self.mapping),
                    "destination",
                    "4",
                    "error",
                    "false",
                    "false",
                    "true",
                ]
            )
        terminal.assert_not_called()
        self.assertFalse(
            any(
                call.args[0].startswith("TRUNCATE")
                for call in self.session.run_sql.call_args_list
            )
        )


class LogTests(unittest.TestCase):
    def check(self, text, mode):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "load.log"
            path.write_text(text)
            loader.check_log(path, mode)

    def test_normal_summary(self):
        self.check(
            "Total rows affected in d.t: Records: 2  Deleted: 0  Skipped: 0  Warnings: 0",
            "error",
        )

    def test_type_warning_even_with_zero_exit_is_error(self):
        for mode in ("error", "skip", "replace"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.check(
                    "WARNING: LOAD DATA error for `d`.`t` in file 'a', error 1265: truncated\n"
                    "Total rows affected in d.t: Records: 2  Deleted: 0  Skipped: 0  Warnings: 1",
                    mode,
                )

    def test_duplicate_allowed_only_in_skip(self):
        text = (
            "\x1b[33mWARNING: \x1b[0mLOAD DATA error for `d`.`t` in file 'a', error 1062: Duplicate\n"
            "Total rows affected in d.t: Records: 2  Deleted: 0  Skipped: 1  Warnings: 1"
        )
        self.check(text, "skip")
        for mode in ("error", "replace"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.check(text, mode)

    def test_unknown_warning_counts_fail(self):
        with self.assertRaises(ValueError):
            self.check(
                "Total rows affected in d.t: Records: 2  Deleted: 0  Skipped: 1  Warnings: 1",
                "skip",
            )

    def test_missing_native_summary_is_error(self):
        with self.assertRaisesRegex(ValueError, "요약이 누락"):
            self.check("Mapped import tables: 1\n", "error")

    def test_native_log_checks_warnings_hidden_from_console(self):
        with tempfile.TemporaryDirectory() as temp:
            console = Path(temp) / "console"
            diagnostic = Path(temp) / "diagnostics"
            console.write_text(
                "Mapped import tables: 1\n"
                "Total rows affected in d.t: Records: 10  Deleted: 0  Skipped: 10  Warnings: 10"
            )
            warning = "Warning: LOAD DATA error for `d`.`t` in file 'a', error 1062: duplicate\n"
            diagnostic.write_text(warning * 10)
            loader.check_log(console, "skip", diagnostic)
            diagnostic.write_text(warning * 9 + warning.replace("1062", "1452"))
            with self.assertRaisesRegex(ValueError, "1452"):
                loader.check_log(console, "skip", diagnostic)

    def test_large_warning_log_uses_bounded_memory(self):
        with tempfile.TemporaryDirectory() as temp:
            console = Path(temp) / "console"
            diagnostic = Path(temp) / "diagnostics"
            count = 50000
            console.write_text(
                "Mapped import tables: 1\n"
                f"Total rows affected in d.t: Records: {count}  Deleted: 0  "
                f"Skipped: {count}  Warnings: {count}"
            )
            with diagnostic.open("w") as stream:
                for i in range(count):
                    stream.write(
                        f"Warning: LOAD DATA error for `d`.`t` in file 'a', error 1062: Duplicate entry '{i}'\n"
                    )
            tracemalloc.start()
            try:
                loader.check_log(console, "skip", diagnostic)
                _current, peak = tracemalloc.get_traced_memory()
            finally:
                tracemalloc.stop()
            self.assertLess(peak, 1_000_000)


if __name__ == "__main__":
    unittest.main()
