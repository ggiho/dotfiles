import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'run_onchange_after_update-sql-clients.sh'


class ClientUpdateTests(unittest.TestCase):
    def test_fast_forward_and_local_edits_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            git = shutil.which('git')
            shims = root / 'shims'
            shims.mkdir()
            source = SOURCE.read_text()
            clients = []
            for tool, branch, variable in [('pgcli', 'feature/atuin-history', 'PGCLI_REVISION'),
                                            ('mycli', 'feature/table-aliases-and-paste-hygiene', 'MYCLI_REVISION')]:
                remote = root / 'remotes' / tool
                remote.mkdir(parents=True)
                def run(*args, cwd=remote):
                    return subprocess.check_output([git, '-C', str(cwd), *args], stderr=subprocess.DEVNULL, text=True).strip()
                run('init', '-b', branch)
                run('config', 'user.name', 'Install Test')
                run('config', 'user.email', 'test@example.invalid')
                (remote / 'client.txt').write_text('initial')
                run('add', 'client.txt')
                run('-c', 'commit.gpgsign=false', 'commit', '-m', 'initial')
                checkout = root / 'src/github.com/ggiho' / tool
                checkout.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run([git, 'clone', str(remote), str(checkout)], check=True, capture_output=True)
                (remote / 'feature.txt').write_text('roundtrip')
                run('add', 'feature.txt')
                run('-c', 'commit.gpgsign=false', 'commit', '-m', 'feature')
                revision = run('rev-parse', 'HEAD')
                import re
                source = re.sub(variable + r'=[0-9a-f]+', variable + '=' + revision, source)
                clients.append((checkout, branch, revision))
            script = root / 'update.sh'
            script.write_text(source)
            (shims / 'git').write_text('''#!/usr/bin/env python3
import os,sys
args=[arg.replace('https://github.com/ggiho/', os.environ['TEST_REMOTES']+'/').removesuffix('.git') if arg.startswith('https://github.com/ggiho/') else arg for arg in sys.argv[1:]]
os.execv(os.environ['TEST_GIT'], [os.environ['TEST_GIT']]+args)
''')
            (shims / 'uv').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_UV_LOG"\n')
            for p in shims.iterdir():
                p.chmod(0o755)
            startup_log = root / 'startup.log'
            for tool in ['mycli', 'pgcli']:
                (shims / tool).write_text('#!/bin/sh\nprintf "%s %s\\n" "$(basename "$0")" "$*" >> "$TEST_STARTUP_LOG"\n')
                (shims / tool).chmod(0o755)
            log = root / 'uv.log'
            env = dict(os.environ, PATH=str(shims)+os.pathsep+os.environ['PATH'],
                       DOTFILES_SRC_ROOT=str(root / 'src'), TEST_REMOTES=str(root / 'remotes'),
                       TEST_GIT=git, TEST_UV_LOG=str(log), TEST_STARTUP_LOG=str(startup_log))
            first = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            for checkout, branch, revision in clients:
                self.assertEqual(subprocess.check_output([git, '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip(), revision)
                self.assertEqual((checkout / 'feature.txt').read_text(), 'roundtrip')
            invocations = log.read_text().splitlines()
            self.assertEqual(len(invocations), 2)
            self.assertTrue(all('--compile-bytecode' in call for call in invocations))
            self.assertEqual(startup_log.read_text().splitlines(), ['pgcli --version', 'mycli --version'])
            # Never initialize a stale command after its replacement failed.
            startup_log.unlink()
            (shims / 'uv').write_text('#!/bin/sh\nexit 1\n')
            failed = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
            self.assertEqual(failed.returncode, 0, failed.stderr)
            self.assertEqual(failed.stdout.count('editable installation failed'), 2)
            self.assertFalse(startup_log.exists())
            (shims / 'uv').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_UV_LOG"\n')
            # A developer's tracked edits and branch choice must survive updates.
            (clients[1][0] / 'client.txt').write_text('local edits')
            subprocess.run([git, '-C', str(clients[0][0]), 'checkout', '-b', 'local-work'], check=True, capture_output=True)
            log.unlink()
            second = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(second.stdout.count('different branch or local edits'), 2)
            self.assertEqual((clients[1][0] / 'client.txt').read_text(), 'local edits')
            self.assertFalse(log.exists())
            self.assertFalse(startup_log.exists())


if __name__ == '__main__':
    unittest.main()
