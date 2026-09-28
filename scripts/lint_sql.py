"""
Static checks for the SQL examples in this repo.

Each rule catches a defect that has actually broken an example here:

  yaml-comment     A SQL "--" comment inside a FROM SPECIFICATION $$ ... $$
                   YAML block. YAML treats it as content and CREATE AGENT fails.
  identifier-concat
                   IDENTIFIER($a || '.' || $b). Snowflake rejects expressions
                   inside IDENTIFIER(); set a precomputed variable first.
  missing-teardown An example folder with a setup/create script and no
                   teardown.sql alongside it (or in scripts/).

Usage:
    python scripts/lint_sql.py            # lint the whole repo
    python scripts/lint_sql.py path ...   # lint specific files

Exits 1 if any problem is found.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SPEC_OPEN = re.compile(r"FROM\s+SPECIFICATION\s*(\$\$)?\s*$", re.IGNORECASE)
IDENT_CONCAT = re.compile(r"IDENTIFIER\(\s*\$\w+\s*\|\|", re.IGNORECASE)
SETUP_NAMES = re.compile(r"^(setup|create-.*|.*-agent)\.sql$")


def lint_file(path: Path) -> list[str]:
    problems = []
    lines = path.read_text(encoding="utf-8").splitlines()
    in_spec = False
    pending_open = False
    rel = path.relative_to(ROOT)

    for n, line in enumerate(lines, start=1):
        stripped = line.strip()

        if in_spec:
            if stripped.startswith("$$"):
                in_spec = False
            elif stripped.startswith("--"):
                problems.append(f"{rel}:{n}: yaml-comment: SQL comment inside a "
                                "SPECIFICATION block; use '#' or move it outside")
            continue

        match = SPEC_OPEN.search(line)
        if match:
            if match.group(1):
                in_spec = True
            else:
                pending_open = True
            continue
        if pending_open:
            pending_open = False
            if stripped == "$$":
                in_spec = True
                continue

        if not stripped.startswith("--") and IDENT_CONCAT.search(line):
            problems.append(f"{rel}:{n}: identifier-concat: expression inside "
                            "IDENTIFIER(); SET a precomputed variable instead")
    return problems


def lint_teardowns() -> list[str]:
    problems = []
    folders = {p.parent for p in ROOT.rglob("*.sql") if SETUP_NAMES.match(p.name)}
    for folder in sorted(folders):
        if ".cortex" in folder.parts:
            continue
        if not ((folder / "teardown.sql").exists()
                or (folder / "scripts" / "teardown.sql").exists()):
            problems.append(f"{folder.relative_to(ROOT)}: missing-teardown: "
                            "add a teardown.sql")
    return problems


def main(argv: list[str]) -> int:
    if argv:
        files = [Path(a).resolve() for a in argv]
        problems = []
    else:
        files = sorted(p for p in ROOT.rglob("*.sql") if ".cortex" not in p.parts)
        problems = lint_teardowns()
    for f in files:
        problems.extend(lint_file(f))

    for p in problems:
        print(p)
    print(f"{len(files)} file(s) checked, {len(problems)} problem(s)", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
