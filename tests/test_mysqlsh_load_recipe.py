"""Run the load recipe with fake CLI tools; never connect to a database."""

import json
import os
import re
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "dot_config/justfile"


class LoadRecipeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name).resolve()
        self.dump = self.work / "dump"
        self.dump.mkdir()
        (self.dump / "@.json").write_text("{}")
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.capture = self.work / "calls.jsonl"
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            CAPTURE=str(self.capture),
        )
        self.tool(
            "fzf",
            """import json, os, sys
rows = sys.stdin.read().splitlines()
prompt = next((arg for arg in sys.argv if arg.startswith('--prompt=')), '')
if 'load mapping>' in prompt:
    with open(os.environ['CAPTURE'] + '.fzf', 'a') as f:
        f.write(json.dumps(rows) + '\\n')
    if os.environ.get('CANCEL_MAPPING'):
        sys.exit(130)
    wanted = os.environ.get('PICK_MAPPING')
    if wanted:
        print(next(row for row in rows if wanted in row))
        sys.exit(0)
print(rows[0] if rows else '')
""",
        )
        self.tool("security", "print('test-password')")
        self.tool(
            "mysqlsh",
            """import json, os, sys
with open(os.environ['CAPTURE'], 'a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\\n')
output = os.environ.get('MYSQLSH_OUTPUT', 'loaded')
for arg in sys.argv:
    if arg.startswith('--log-file='):
        with open(arg.split('=', 1)[1], 'w') as f:
            f.write(output)
print(output)
sys.exit(int(os.environ.get('MYSQLSH_EXIT', '0')))
""",
        )

    def tool(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + body + "\n")
        path.chmod(0o755)

    def run_recipe(self, **overrides):
        params = {
            "host": "example.invalid",
            "user": "tester",
            "port": "3306",
            "threads": "4",
            "target_schema": "",
            "on_exist": "error",
            "force_drop": "false",
            "mapping": "",
            "duplicates": "error",
            "dry_run": "false",
            "interactive": "false",
            "clear_target": "false",
            "MYSQLSH_LOAD_PY": str(ROOT / "lib/mysqlsh_load.py"),
        }
        params.update(overrides)
        lines = (ROOT / "justfile").read_text().splitlines()
        start = next(
            i for i, line in enumerate(lines) if line.startswith("mysqlsh-load host ")
        )
        body = []
        for line in lines[start + 1 :]:
            if line and not line.startswith(" "):
                break
            body.append(line.removeprefix("  "))
        script = re.sub(
            r"\{\{(?:quote\((\w+)\)|(\w+))\}\}",
            lambda m: shlex.quote(params[m[1]]) if m[1] else params[m[2]],
            "\n".join(body),
        )
        return subprocess.run(
            ["bash", "-c", script],
            check=False,
            cwd=self.work,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
            input=self.env.get("RECIPE_STDIN"),
        )

    def calls(self):
        return (
            [json.loads(line) for line in self.capture.read_text().splitlines()]
            if self.capture.exists()
            else []
        )

    def test_default_load_and_progress(self):
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        (args,) = self.calls()
        self.assertIn("load-dump", args)
        self.assertIn("--progressFile=./dump/.load_progress_example.invalid_3306", args)
        self.assertNotIn("--dropExistingObjects=true", args)
        self.assertNotIn("--ignoreExistingObjects=true", args)
        self.assertNotIn("test-password", " ".join(args))

    def test_schema_and_ignore(self):
        result = self.run_recipe(target_schema="destination", on_exist="ignore")
        self.assertEqual(result.returncode, 0, result.stderr)
        (args,) = self.calls()
        self.assertIn("--schema=destination", args)
        self.assertIn("--ignoreExistingObjects=true", args)
        self.assertIn(
            "--progressFile=./dump/.load_progress_example.invalid_3306_destination",
            args,
        )

    def test_target_schema_is_shell_quoted(self):
        schema = 'data"$(touch unexpected)'
        result = self.run_recipe(target_schema=schema)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--schema=" + schema, self.calls()[0])
        self.assertFalse((self.work / "unexpected").exists())

    def test_drop_data_dump(self):
        self.assertEqual(self.run_recipe(on_exist="drop").returncode, 0)
        self.assertIn("--dropExistingObjects=true", self.calls()[0])

    def test_ddl_only_drop_is_refused_before_mysqlsh(self):
        (self.dump / "@.json").write_text('{"options":{"ddlOnly":true}}')
        self.assertNotEqual(self.run_recipe(on_exist="drop").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_ddl_only_drop_force_override(self):
        (self.dump / "@.json").write_text('{"options":{"ddlOnly":true}}')
        self.assertEqual(
            self.run_recipe(on_exist="drop", force_drop="true").returncode, 0
        )
        self.assertIn("--dropExistingObjects=true", self.calls()[0])

    def test_process_failure_propagates(self):
        self.env["MYSQLSH_EXIT"] = "7"
        self.assertNotEqual(self.run_recipe().returncode, 0)

    def test_error_output_fails_even_with_zero_exit(self):
        self.env["MYSQLSH_OUTPUT"] = "ERROR: MYSQLSH 53000: failed"
        self.assertNotEqual(self.run_recipe().returncode, 0)

    def mapping_file(self):
        path = self.work / "mapping.json"
        path.write_text('{"tables":{"source.people":{}}}')
        return str(path)

    def test_mapping_routes_to_python_without_ddl_or_progress(self):
        result = self.run_recipe(
            mapping=self.mapping_file(), target_schema="destination"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        (args,) = self.calls()
        self.assertIn("--mysql", args)
        self.assertIn("--py", args)
        self.assertIn(str(ROOT / "lib/mysqlsh_load.py"), args)
        self.assertEqual(args[-4:], ["destination", "4", "error", "false"])
        self.assertFalse(
            any("progressFile" in arg or "ExistingObjects" in arg for arg in args)
        )
        self.assertNotIn("load-dump", args)

    def test_mapping_path_is_shell_quoted(self):
        path = self.work / "map '$(touch unexpected)'.json"
        path.write_text("{}")
        result = self.run_recipe(mapping=str(path))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(path), self.calls()[0])
        self.assertFalse((self.work / "unexpected").exists())

    def test_mapping_rejects_drop_and_force_drop(self):
        for params in ({"on_exist": "drop"}, {"force_drop": "true"}):
            with self.subTest(params=params):
                self.assertNotEqual(
                    self.run_recipe(mapping=self.mapping_file(), **params).returncode, 0
                )
                self.assertEqual(self.calls(), [])

    def test_mapping_accepts_ignore_with_row_replacement_without_ddl(self):
        result = self.run_recipe(
            mapping=self.mapping_file(),
            target_schema="reference",
            on_exist="ignore",
            duplicates="replace",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        (args,) = self.calls()
        self.assertEqual(args[-4:], ["reference", "4", "replace", "false"])
        self.assertFalse(any("ExistingObjects" in arg for arg in args))
        self.assertNotIn("load-dump", args)

    def test_interactive_mapping_accepts_ignore(self):
        result = self.run_recipe(interactive="true", on_exist="ignore")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[0][-1], "true")

    def test_mapping_only_options_require_mapping(self):
        for params in ({"duplicates": "skip"}, {"dry_run": "true"}):
            with self.subTest(params=params):
                self.assertNotEqual(self.run_recipe(**params).returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_mapping_warning_exits_unsuccessfully(self):
        self.env["MYSQLSH_OUTPUT"] = (
            "Total rows affected in destination.people: Records: 2  Deleted: 0  Skipped: 0  Warnings: 1"
        )
        self.assertNotEqual(self.run_recipe(mapping=self.mapping_file()).returncode, 0)

    def test_mapping_skip_allows_duplicate_warnings(self):
        self.env["MYSQLSH_OUTPUT"] = (
            "WARNING: LOAD DATA error for `d`.`t` in file 'a', error 1062: Duplicate entry\n"
            "Total rows affected in d.t: Records: 2  Deleted: 0  Skipped: 1  Warnings: 1"
        )
        self.assertEqual(
            self.run_recipe(mapping=self.mapping_file(), duplicates="skip").returncode,
            0,
        )

    def test_mapping_dry_run_reports_no_data_change(self):
        result = self.run_recipe(mapping=self.mapping_file(), dry_run="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("데이터 변경 없음", result.stdout)
        self.assertNotIn("Loaded:", result.stdout)

    def test_interactive_does_not_require_an_existing_mapping_file(self):
        result = self.run_recipe(interactive="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[0][-3:], ["error", "false", "true"])
        self.assertNotIn("load-dump", self.calls()[0])

    def test_interactive_cancel_does_not_report_loaded(self):
        self.env["MYSQLSH_OUTPUT"] = "Mapped load cancelled"
        result = self.run_recipe(interactive="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("데이터 변경 없음", result.stdout)
        self.assertNotIn("Loaded:", result.stdout)

    def test_interactively_selected_duplicate_policy_controls_log_check(self):
        self.env["MYSQLSH_OUTPUT"] = (
            "Mapped duplicate policy: skip\n"
            "WARNING: LOAD DATA error for `d`.`t` in file 'a', error 1062: duplicate\n"
            "Total rows affected in d.t: Records: 2  Deleted: 0  Skipped: 1  Warnings: 1"
        )
        result = self.run_recipe(interactive="true", duplicates="error")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_saved_mapping_is_selected_after_dump(self):
        path = self.dump / "mapping_saved.json"
        path.write_text('{"tables":{"source.people":{}}}')
        self.env["PICK_MAPPING"] = path.name
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(path), self.calls()[0])
        self.assertNotIn("load-dump", self.calls()[0])

    def test_picker_finds_custom_names_and_excludes_dump_metadata(self):
        path = self.work / "custom map.json"
        path.write_text('{"tables":{"source.people":{}}}')
        (self.dump / "schema.json").write_text('{"tables":["people"]}')
        (self.work / "unrelated.json").write_text('{"message":"not a mapping"}')
        self.env["PICK_MAPPING"] = path.name
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(path), self.calls()[0])
        rows = json.loads(Path(str(self.capture) + ".fzf").read_text().strip())
        self.assertFalse(
            any(
                "schema.json" in row or "unrelated.json" in row or "@.json" in row
                for row in rows
            )
        )

    def test_cancel_mapping_picker_exits_before_database_connection(self):
        path = self.dump / "mapping_saved.json"
        path.write_text('{"tables":{"source.people":{}}}')
        self.env["CANCEL_MAPPING"] = "true"
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertNotIn("Loaded:", result.stdout)

    def test_no_mapping_choice_preserves_normal_load(self):
        path = self.dump / "mapping_saved.json"
        path.write_text('{"tables":{"source.people":{}}}')
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("load-dump", self.calls()[0])
        self.assertTrue(Path(str(self.capture) + ".fzf").is_file())

    def test_explicit_mapping_bypasses_file_picker(self):
        result = self.run_recipe(mapping=self.mapping_file())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(Path(str(self.capture) + ".fzf").exists())

    def test_interactive_picker_can_reuse_saved_mapping(self):
        path = self.dump / "mapping_saved.json"
        path.write_text('{"tables":{"source.people":{}}}')
        self.env["PICK_MAPPING"] = path.name
        result = self.run_recipe(interactive="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(path), self.calls()[0])
        self.assertEqual(self.calls()[0][-1], "true")

    def test_interactive_picker_can_start_new_mapping(self):
        path = self.dump / "mapping_saved.json"
        path.write_text('{"tables":{"source.people":{}}}')
        result = self.run_recipe(interactive="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.calls()[0]
        self.assertNotIn(str(path), args)
        self.assertEqual(args[-1], "true")
        self.assertTrue(Path(str(self.capture) + ".fzf").is_file())

    def test_manual_mapping_path_can_select_a_file_outside_search_depth(self):
        self.mapping_file()
        deep = self.work / "nested" / "deeper"
        deep.mkdir(parents=True)
        path = deep / "other.json"
        path.write_text('{"tables":{"source.people":{}}}')
        self.env["PICK_MAPPING"] = "[매핑 파일 경로 직접 입력]"
        self.env["RECIPE_STDIN"] = str(path) + "\n"
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(path), self.calls()[0])

    def test_empty_manual_mapping_path_cancels(self):
        self.mapping_file()
        self.env["PICK_MAPPING"] = "[매핑 파일 경로 직접 입력]"
        self.env["RECIPE_STDIN"] = "\n"
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_mapping_menu_is_shown_without_saved_files(self):
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = json.loads(Path(str(self.capture) + ".fzf").read_text().strip())
        self.assertIn("[새 테이블·컬럼 매핑]", rows)
        self.assertIn("load-dump", self.calls()[0])

    def test_new_table_mapping_starts_wizard_without_a_json_file(self):
        self.env["PICK_MAPPING"] = "[새 테이블·컬럼 매핑]"
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("load-dump", self.calls()[0])
        self.assertIn("--file", self.calls()[0])
        self.assertEqual(self.calls()[0][-1], "true")

    def test_empty_mapping_menu_can_be_cancelled_before_connecting(self):
        self.env["CANCEL_MAPPING"] = "true"
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_clear_target_routes_to_data_only_helper_with_and_without_mapping(self):
        for mapping in ("", self.mapping_file()):
            with self.subTest(mapping=mapping):
                result = self.run_recipe(mapping=mapping, clear_target="true")
                self.assertEqual(result.returncode, 0, result.stderr)
                args = self.calls()[-1]
                self.assertNotIn("load-dump", args)
                self.assertEqual(args[-2:], ["false", "true"])

    def test_clear_target_rejects_table_drop_before_connecting(self):
        result = self.run_recipe(clear_target="true", on_exist="drop")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
