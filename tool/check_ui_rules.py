#!/usr/bin/env python3
"""Static guard rails for the Rain FUI UI layer.

The project spec has three absolute rules that are cheap to check by reading
source and impossible to notice once a build is shipping (this phase forbids
building), so they are enforced here instead:

1. no blur anywhere (``BackdropFilter`` / ``ImageFilter`` / ``Acrylic``),
2. icons only from ``fluentui_system_icons`` (no Material / Cupertino icons),
3. no user-visible English literals outside the i18n catalogs and
   ``LanguageActivity``.

Rule 3 is heuristic: it reports literal string arguments handed to widgets and
tooltips so a human can confirm they are not copy. Rule 1 and 2 are hard
failures. Exit code 1 means "do not ship".

Usage: ``python3 tool/check_ui_rules.py [--strict]`` from the repo root.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"

# Directories/files that may contain literal text: the catalogs are data, and
# LanguageActivity is intentionally English-only (spec §4).
COPY_EXEMPT = {
    Path("lib/i18n"),
    Path("lib/activities/language_activity.dart"),
}

HARD_PATTERNS = {
    "blur": re.compile(r"\b(BackdropFilter|ImageFilter|Acrylic|BackdropGroup)\b"),
    "material-icons": re.compile(r"\b(CupertinoIcons|Icons\.[a-z])"),
}

# `Text('literal')`, `tooltip: 'literal'`, `title: Text("literal")` …
LITERAL_TEXT = re.compile(
    r"""(?:\bText\(\s*|\btooltip:\s*|\blabel:\s*|\btitle:\s*|\bsubtitle:\s*|\bhint:\s*|\bplaceholder:\s*)['"]([^'"\n]{2,})['"]"""
)

ALLOWED_LITERAL = re.compile(
    r"^(?:[\s·:.,/\\|+\-–—]*|\$\{[^}]*\}|[A-Za-z]:\\\\?|https?://\S+)$"
)


class Finding(NamedTuple):
    kind: str
    path: Path
    line: int
    text: str


def relative(path: Path) -> Path:
    try:
        return path.relative_to(ROOT)
    except ValueError:  # pragma: no cover - defensive
        return path


def is_copy_exempt(rel: Path) -> bool:
    return any(rel == p or str(rel).startswith(str(p)) for p in COPY_EXEMPT)


def scan() -> "list[Finding]":
    findings: "list[Finding]" = []
    for path in sorted(LIB.rglob("*.dart")):
        rel = relative(path)
        if rel.parts[:1] == ("i18n",):
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        in_block_comment = False
        for number, line in enumerate(lines, start=1):
            stripped = line.strip()
            if in_block_comment:
                if "*/" in stripped:
                    in_block_comment = False
                continue
            if stripped.startswith("/*"):
                in_block_comment = "*/" not in stripped
                continue
            if stripped.startswith("//") or stripped.startswith("///"):
                continue

            for kind, pattern in HARD_PATTERNS.items():
                if pattern.search(line):
                    findings.append(Finding(kind, rel, number, stripped))
            if is_copy_exempt(rel):
                continue
            for match in LITERAL_TEXT.finditer(line):
                value = match.group(1).strip()
                if not value or ALLOWED_LITERAL.match(value):
                    continue
                findings.append(Finding("literal-copy", rel, number, stripped))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="treat literal-copy advisories as failures too",
    )
    args = parser.parse_args()

    findings = scan()
    hard = [f for f in findings if f.kind != "literal-copy"]
    advisory = [f for f in findings if f.kind == "literal-copy"]

    for finding in hard:
        print(f"HARD  {finding.kind:14s} {finding.path}:{finding.line}")
        print(f"      {finding.text}")
    for finding in advisory:
        print(f"REVIEW literal-copy  {finding.path}:{finding.line}")
        print(f"      {finding.text}")

    if not findings:
        print("No findings: no blur, no Material/Cupertino icons, no stray literals.")

    if hard:
        print(f"\n{len(hard)} hard violation(s).")
        return 1
    if advisory and args.strict:
        print(f"\n{len(advisory)} literal-copy finding(s) under --strict.")
        return 1
    if advisory:
        print(
            f"\n{len(advisory)} literal string(s) to eyeball; "
            "re-run with --strict to fail on them."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
