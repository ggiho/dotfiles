#!/usr/bin/env python3
"""Render TSV on stdin as a bordered table.

Used by the ddb-* recipes in ~/.config/justfile/justfile. The first input line is
the header row.

Why Python and not awk: macOS awk counts bytes in length(), so any CJK value (and
the ellipsis used for truncation) makes every border in the table misalign. East
Asian Wide/Fullwidth characters occupy two terminal cells and have to be measured
as such.

Environment:
  COLOR=1   emit ANSI colour (catppuccin mocha, matching the fzf/mycli theme)
  CELL=N    truncate each cell to N display columns, ending with an ellipsis
"""

import os
import re
import sys
import unicodedata

WIDE = frozenset("WF")


def dw(s: str) -> int:
    """Display width of s in terminal cells."""
    return sum(2 if unicodedata.east_asian_width(c) in WIDE else 1 for c in s)


def cut(s: str, limit: int) -> str:
    """Truncate s to at most `limit` display columns, marking the cut."""
    if dw(s) <= limit:
        return s
    out, w = "", 0
    for c in s:
        cw = dw(c)
        if w + cw > limit - 1:
            break
        out += c
        w += cw
    return out + "…"


PALETTE = {
    "border": "\033[38;2;88;91;112m",     # surface2
    "header": "\033[1;38;2;203;166;247m",  # mauve
    "value": "\033[38;2;205;214;244m",    # text
    "first": "\033[38;2;137;180;250m",    # blue
    "off": "\033[0m",
}

NUMERIC = re.compile(r"^[0-9][0-9,.]*( ?[KMGT]?B)?$")


def main() -> int:
    colour = PALETTE if os.environ.get("COLOR") == "1" else dict.fromkeys(PALETTE, "")

    rows = [line.rstrip("\n").split("\t") for line in sys.stdin if line.strip("\n")]
    if not rows:
        print("(no rows)")
        return 0

    limit = int(os.environ.get("CELL") or 0)
    if limit > 1:
        rows = [[cut(c, limit) for c in r] for r in rows]

    ncol = max(len(r) for r in rows)
    rows = [r + [""] * (ncol - len(r)) for r in rows]
    widths = [max(dw(r[i]) for r in rows) for i in range(ncol)]

    # Right-align only when every populated data cell reads as a number or a size,
    # so counts and byte sizes line up on their last digit.
    body = rows[1:]
    right = [
        bool(body) and all(NUMERIC.match(r[i]) for r in body if r[i])
        for i in range(ncol)
    ]

    def pad(text: str, i: int) -> str:
        gap = " " * (widths[i] - dw(text))
        return gap + text if right[i] else text + gap

    def rule(left: str, mid: str, rightc: str) -> str:
        return colour["border"] + left + mid.join(
            "─" * (w + 2) for w in widths
        ) + rightc + colour["off"]

    bar = colour["border"] + "│" + colour["off"]

    def render(cells, style_for):
        parts = [
            f" {style_for(i)}{pad(c, i)}{colour['off']} "
            for i, c in enumerate(cells)
        ]
        return bar + bar.join(parts) + bar

    print(rule("╭", "┬", "╮"))
    print(render(rows[0], lambda i: colour["header"]))
    print(rule("├", "┼", "┤"))
    for r in body:
        print(render(r, lambda i: colour["first"] if i == 0 else colour["value"]))
    print(rule("╰", "┴", "╯"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
