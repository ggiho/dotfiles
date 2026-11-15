"""Check activation ordering with isolated paths and fake system commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class OmniBootstrapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = subprocess.check_output(
            ["chezmoi", "execute-template", "--file", str(REPO / "run_onchange_after_omniwm.sh.tmpl")],
            cwd=REPO, text=True,
        )

    def activate(self, fail_compile=False):
        with tempfile.TemporaryDirectory(prefix="omni-bootstrap-test-") as tmp:
            root = Path(tmp)
            config = root / "config-home/.config/omniwm"
            config.mkdir(parents=True)
            (config / "shortcut-helper.swift").write_text("test source")
            previous = config / "previous"
            previous.write_text("old helper")
            (config / "shortcut-helper").symlink_to(previous)
            app, shims, log = root / "OmniWM.app", root / "shims", root / "commands.log"
            app.mkdir()
            shims.mkdir()
            scripts = {
                "uname": "#!/bin/sh\necho Darwin\n",
                "swiftc": """#!/bin/bash
if [ "${OMNI_TEST_FAIL_COMPILE:-0}" = 1 ]; then exit 9; fi
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; target="$1"; break; fi
  shift
done
printf '#!/bin/sh\\nexit 0\\n' > "$target"
chmod +x "$target"
""",
                "launchctl": "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$OMNI_TEST_LOG\"\n",
                "pgrep": "#!/bin/sh\nexit 1\n",
                "pkill": "#!/bin/sh\nexit 1\n",
            }
            for name, content in scripts.items():
                path = shims / name
                path.write_text(content)
                path.chmod(0o755)
            # Substitute only filesystem roots; never change the real home or services.
            script = self.script.replace("/Applications/OmniWM.app", str(app))
            script = script.replace('"$HOME/', '"' + str(root / "config-home") + "/")
            path = root / "bootstrap.sh"
            path.write_text(script)
            env = dict(os.environ, PATH=str(shims) + os.pathsep + os.environ["PATH"],
                       OMNI_TEST_LOG=str(log), OMNI_TEST_FAIL_COMPILE=str(int(fail_compile)))
            result = subprocess.run(["bash", str(path)], env=env, capture_output=True, text=True)
            if fail_compile:
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((config / "shortcut-helper").resolve(), previous.resolve())
                self.assertEqual(previous.read_text(), "old helper")
                self.assertFalse(log.exists())
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotEqual((config / "shortcut-helper").resolve(), previous.resolve())
                self.assertEqual(previous.read_text(), "old helper")
                commands = log.read_text().splitlines()
                self.assertEqual(sum(c.startswith("bootstrap ") for c in commands), 2)
                self.assertLess(next(i for i,c in enumerate(commands) if "disable " in c),
                                next(i for i,c in enumerate(commands) if c.startswith("bootstrap ")))
                self.assertFalse(list(config.rglob("*.new")))
                self.assertFalse(list(config.rglob("*.self-test")))

    def test_compile_failure_preserves_existing_helper_and_services(self):
        self.activate(fail_compile=True)

    def test_success_builds_before_switching_services(self):
        self.activate()


if __name__ == "__main__":
    unittest.main()
