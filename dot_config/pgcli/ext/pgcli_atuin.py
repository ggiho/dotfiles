"""Give pgcli atuin-backed history and an atuin Up-arrow picker, without
touching the installed package.

Imported before pgcli.main.cli() runs (see the pgcli shell alias). It rebinds
two module globals in pgcli.main -- FileHistory and pgcli_bindings -- so nothing
inside the uv-managed venv is modified and `uv tool upgrade pgcli` cannot undo it.

Settings are read straight from ~/.config/pgcli/config:

    [main]
    atuin_history = True
    atuin_author = pgcli
    atuin_keys = True
"""

import hashlib
import logging
import os
from shutil import which
import subprocess

from prompt_toolkit.filters import shift_selection_mode
from prompt_toolkit.history import FileHistory, History

logger = logging.getLogger(__name__)

ACCEPT_PREFIX = "__atuin_accept__:"
TIMEOUT = 5.0


def _config():
    from configobj import ConfigObj
    from pgcli.config import config_location

    path = os.path.join(config_location(), "config")
    main = ConfigObj(path, interpolation=False, encoding="utf-8").get("main", {})
    truthy = ("true", "yes", "on", "1")
    return {
        "history": str(main.get("atuin_history", "False")).lower() in truthy,
        "keys": str(main.get("atuin_keys", "False")).lower() in truthy,
        "author": main.get("atuin_author", "pgcli"),
    }


def session_id(author):
    """Stable session id: atuin's picker ignores --author but honours
    --filter-mode session, so everything pgcli writes shares one session."""
    return hashlib.sha256(f"pgcli-history:{author}".encode()).hexdigest()[:32]


def _atuin(*args, env=None):
    try:
        proc = subprocess.run(("atuin", *args), capture_output=True, text=True, timeout=TIMEOUT, env=env)
    except (OSError, subprocess.SubprocessError) as e:
        logger.debug("atuin %s failed: %s", args[:1], e)
        return None
    if proc.returncode != 0:
        logger.debug("atuin %s exited %s: %s", args[:1], proc.returncode, proc.stderr.strip())
        return None
    return proc.stdout


class AtuinHistory(History):
    """Same contract as mycli's backend: --reverse for newest-first (atuin's
    default is oldest-first despite its --help), --include-duplicates so
    frequency survives, and no `history end` because the exit code is unknown
    when prompt_toolkit stores the line."""

    def __init__(self, author="pgcli", limit=5000, legacy=None):
        super().__init__()
        self.author = author
        self.limit = limit
        self.legacy = legacy

    def load_history_strings(self):
        args = [
            "search", "--author", self.author, "--include-duplicates",
            "--reverse", "--print0", "--cmd-only", "--limit", str(self.limit),
        ]
        out = _atuin(*args)
        entries = [r for r in out.split("\0") if r] if out is not None else []
        if self.legacy is not None:
            entries.extend(self.legacy.load_history_strings())
        return entries

    def store_string(self, string):
        _atuin(
            "history", "start", "--author", self.author, string,
            env=dict(os.environ, ATUIN_SESSION=session_id(self.author)),
        )


def search_history(event, author, up_key_binding=False):
    """atuin draws its TUI on stdout and prints the pick on stderr."""
    buffer = event.current_buffer
    args = ["atuin", "search", "-i", "--filter-mode", "session"]
    if up_key_binding:
        args.append("--shell-up-key-binding")
    env = dict(os.environ, ATUIN_SHELL="zsh", ATUIN_QUERY=buffer.text, ATUIN_SESSION=session_id(author))
    try:
        proc = subprocess.run(args, stdout=None, stderr=subprocess.PIPE, text=True, env=env)
    except (OSError, subprocess.SubprocessError) as e:
        logger.debug("atuin search could not run: %s", e)
        return False

    event.app.renderer.reset()
    event.app.invalidate()

    pick = proc.stderr.strip()
    if not pick:
        return True
    accept = pick.startswith(ACCEPT_PREFIX)
    if accept:
        pick = pick[len(ACCEPT_PREFIX):]
    buffer.text = pick
    buffer.cursor_position = len(pick)
    if accept:
        buffer.validate_and_handle()
    return True


def install():
    import pgcli.main as pgcli_main

    cfg = _config()
    if not cfg["history"] or which("atuin") is None:
        return False

    author = cfg["author"]

    def history_factory(path):
        # pgcli's own file history becomes the legacy tail, so pre-atuin
        # queries stay reachable without importing them.
        return AtuinHistory(author=author, legacy=FileHistory(path))

    pgcli_main.FileHistory = history_factory

    if cfg["keys"]:
        original = pgcli_main.pgcli_bindings

        def patched(pgcli_obj):
            kb = original(pgcli_obj)

            @kb.add("up", filter=~shift_selection_mode)
            def _(event):
                buf = event.current_buffer
                # Mirror atuin's zsh widget: single-line buffers only, so Up
                # still moves through completions and multi-line SQL.
                if buf.complete_state or "\n" in buf.text:
                    buf.auto_up(count=event.arg)
                    return
                if not search_history(event, author, up_key_binding=True):
                    buf.auto_up(count=event.arg)

            return kb

        pgcli_main.pgcli_bindings = patched

    return True


install()
