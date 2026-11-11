"""Exercise the release installer with isolated homes and local release fixtures."""
import hashlib
import io
import os
import shlex
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'run_onchange_after_install-ddb-tui.sh'


class InstallTests(unittest.TestCase):
    def install(self, arch='arm64', cargo=False, bad_checksum=False, missing_viewer=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home, shims, fixtures = [root / name for name in ['home', 'shims', 'fixtures']]
            for path in [home, shims, fixtures]:
                path.mkdir()
            target = 'aarch64-apple-darwin' if arch == 'arm64' else 'x86_64-apple-darwin'
            name = f'ddb-tui-v0.3.3-{target}'
            archive = fixtures / f'{name}.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                for binary in ['ddb-tui', 'sql-viewer']:
                    if binary == 'sql-viewer' and missing_viewer:
                        continue
                    data = f'#!/bin/sh\necho {binary}\n'.encode()
                    entry = tarfile.TarInfo(f'{name}/{binary}')
                    entry.size, entry.mode = len(data), 0o755
                    tar.addfile(entry, io.BytesIO(data))
            digest = '0' * 64 if bad_checksum else hashlib.sha256(archive.read_bytes()).hexdigest()
            archive.with_suffix('.gz.sha256').write_text(f'{digest}  {archive.name}\n')
            (shims / 'uname').write_text('#!/bin/sh\nif [ "$1" = "-s" ]; then echo Darwin; else echo "$INSTALL_TEST_ARCH"; fi\n')
            (shims / 'curl').write_text('#!/bin/bash\nfor arg; do url="$arg"; done\ncp "$INSTALL_TEST_FIXTURES/${url##*/}" .\n')
            for shim in shims.iterdir():
                shim.chmod(0o755)
            if cargo:
                binary = home / '.cargo/bin/ddb-tui'
                binary.parent.mkdir(parents=True)
                binary.write_text('cargo version')
                binary.chmod(0o755)
            if bad_checksum or missing_viewer:
                binary = home / '.local/bin/sql-viewer'
                binary.parent.mkdir(parents=True)
                binary.write_text('existing viewer')
            env = dict(os.environ, HOME=str(home), CARGO_HOME=str(home / '.cargo'),
                       PATH=str(shims) + os.pathsep + os.environ['PATH'],
                       INSTALL_TEST_ARCH=arch, INSTALL_TEST_FIXTURES=str(fixtures))
            result = subprocess.run(['bash', str(SCRIPT)], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            if bad_checksum or missing_viewer:
                self.assertEqual((home / '.local/bin/sql-viewer').read_text(), 'existing viewer')
                self.assertFalse((home / '.local/bin/ddb-tui').exists())
                self.assertIn('[WARN]', result.stdout)
                return
            self.assertTrue(os.access(home / '.local/bin/sql-viewer', os.X_OK))
            self.assertEqual((home / '.local/bin/ddb-tui').exists(), not cargo)
            if cargo:
                self.assertEqual((home / '.cargo/bin/ddb-tui').read_text(), 'cargo version')
            else:
                self.assertEqual(os.readlink(home / '.local/bin/ddb'), 'ddb-tui')
            again = subprocess.run(['bash', str(SCRIPT)], env=env, text=True, capture_output=True)
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertFalse(list((home / '.local/bin').glob('.*.*')))

    def test_apple_silicon(self):
        self.install()

    def test_intel(self):
        self.install(arch='x86_64')

    def test_cargo_ddb_does_not_skip_viewer(self):
        self.install(cargo=True)

    def test_corrupt_download_preserves_installation(self):
        self.install(bad_checksum=True)

    def test_incomplete_bundle_preserves_installation(self):
        self.install(missing_viewer=True)


class PagerCommandTests(unittest.TestCase):
    def test_home_path_expands_with_direct_process_invocation(self):
        source = SCRIPT.parent
        with tempfile.TemporaryDirectory(prefix='sql pager home ') as directory:
            viewer = Path(directory) / '.local/libexec/sql-pager/viewer'
            viewer.parent.mkdir(parents=True)
            viewer.write_text('#!/bin/sh\ncat\n')
            viewer.chmod(0o755)
            for config in [source / 'dot_myclirc', source / 'dot_config/pgcli/config']:
                setting = next(line.split('=', 1)[1].strip() for line in config.read_text().splitlines() if line.startswith('pager ='))
                result = subprocess.run(shlex.split(setting), input=b'original result\n', capture_output=True,
                                        env=dict(os.environ, HOME=directory))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, b'original result\n')


if __name__ == '__main__':
    unittest.main()
