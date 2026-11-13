#!/usr/bin/env python3
"""No project's name or path in product-kit's code (#32).

What's particular to a project goes in its `.product-kit.json`. Notes may name the project an
idea came from (`NetworkMonitor#431`); code may not. This reads every tool's code with its
comments and docstrings taken out, and fails on any project's name left in what remains.
"""
import ast
import io
import pathlib
import re
import sys
import tokenize

ROOT = pathlib.Path(__file__).resolve().parent.parent
# The projects that use product-kit, and their telling paths and arguments.
NAMES = re.compile(r"NetworkMonitor|networkmonitor|claude-profiles|ClaudeProfiles|home-control|Home Control"
                   r"|BatteryTrace|speaker-keeper|Resources/Localization|-popoverScreen")


def python_code(path: pathlib.Path) -> list[tuple[int, str]]:
    """The file's lines without comments and docstrings."""
    text = path.read_text(encoding="utf-8")
    drop: set[int] = set()
    for node in ast.walk(ast.parse(text)):
        body = getattr(node, "body", None)
        if isinstance(body, list) and body and isinstance(body[0], ast.Expr) \
                and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str):
            drop.update(range(body[0].lineno, body[0].end_lineno + 1))
    lines = text.split("\n")
    for tok in tokenize.generate_tokens(io.StringIO(text).readline):
        if tok.type == tokenize.COMMENT:
            row, col = tok.start
            lines[row - 1] = lines[row - 1][:col]
    return [(n, l) for n, l in enumerate(lines, 1) if n not in drop]


def swift_code(path: pathlib.Path) -> list[tuple[int, str]]:
    out = []
    for n, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        code, quoted, i = [], False, 0
        while i < len(line):
            c = line[i]
            if c == "\\" and quoted:
                code.append(line[i:i + 2]); i += 2; continue
            if c == '"':
                quoted = not quoted
            if not quoted and line.startswith("//", i):
                break
            code.append(c); i += 1
        out.append((n, "".join(code)))
    return out


def shell_code(path: pathlib.Path) -> list[tuple[int, str]]:
    return [(n, re.sub(r"(^|\s)#.*$", "", l)) for n, l in enumerate(path.read_text(encoding="utf-8").split("\n"), 1)]


def main() -> int:
    found = []
    for path in sorted((ROOT / "bin").iterdir()) + sorted((ROOT / "shots").glob("*.swift")) + sorted((ROOT / "drivers").iterdir()):
        head = path.read_text(encoding="utf-8").split("\n", 1)[0]
        reader = swift_code if path.suffix == ".swift" else python_code if "python" in head else shell_code
        for n, line in reader(path):
            m = NAMES.search(line)
            if m:
                found.append(f"{path.relative_to(ROOT)}:{n}: {m.group(0)} in code: {line.strip()[:120]}")
    if found:
        print("A project's name or path is in product-kit's code; it belongs in that project's config:")
        print("\n".join("  " + f for f in found))
        return 1
    print("generic: no project's name or path in the code")
    return 0


if __name__ == "__main__":
    sys.exit(main())
