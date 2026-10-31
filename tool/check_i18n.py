#!/usr/bin/env python3
"""Static checks for the Rain FUI i18n catalogs.

Verifies, for every catalog in ``lib/i18n/``:

* the key set is exactly the key set of ``en_US.dart`` (no missing, no extras),
* the declaration order matches ``en_US.dart`` (keeps diffs reviewable),
* no value is empty, and no long sentence is duplicated between two keys,
* every ``I18nKey`` constant in ``lib/i18n/i18n_keys.dart`` is covered.

It also reports values that are byte-identical to en-US as an advisory, because
some of them are intentional (``app_title`` is the product name) while others
usually mean an untranslated string.

Exit code 0 when every catalog is structurally sound, 1 otherwise. Run it with
``python3 tool/check_i18n.py`` from the repository root; it needs no Flutter SDK.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
I18N_DIR = ROOT / "lib" / "i18n"
REFERENCE = I18N_DIR / "en_US.dart"
KEYS_FILE = I18N_DIR / "i18n_keys.dart"

#: Values that are allowed to be identical across every locale.
INTENTIONALLY_UNTRANSLATED = {"app_title"}

#: Only sentences at least this long are reported for duplicate values; short
#: labels legitimately share a word ("Home" is both the nav item and the page).
DUPLICATE_MIN_LENGTH = 25

_KEY_AT = re.compile(r"""^\s*'([A-Za-z0-9_]+)'\s*:""", re.M)
_LITERAL = re.compile(r"""'((?:[^'\\\n]|\\.)*)'""")
_CONST_RE = re.compile(
    r"static\s+const\s+String\s+(\w+)\s*=\s*'([A-Za-z0-9_]+)'\s*;"
)


def _unescape(literal: str) -> str:
    return (
        literal.replace(r"\'", "'")
        .replace(r"\\", "\\")
        .replace(r"\n", "\n")
        .replace(r"\t", "\t")
    )


def parse_catalog(path: Path) -> "list[tuple[str, str]]":
    """Return ``(key, value)`` pairs in declaration order.

    `dart format` wraps long entries onto several lines (and can split a string
    into adjacent literals), so each entry is taken as the slice between two key
    positions and all of its single-quoted literals are concatenated.
    """
    text = path.read_text(encoding="utf-8")
    matches = list(_KEY_AT.finditer(text))
    entries: "list[tuple[str, str]]" = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        chunk = text[match.end():end]
        value = "".join(_unescape(part) for part in _LITERAL.findall(chunk))
        entries.append((match.group(1), value.strip()))
    return entries


def declared_keys() -> "list[str]":
    text = KEYS_FILE.read_text(encoding="utf-8")
    return [key for _, key in _CONST_RE.findall(text)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--no-advisory",
        action="store_true",
        help="hide the untranslated-value advisory",
    )
    args = parser.parse_args()

    if not REFERENCE.exists():
        print(f"error: missing reference catalog {REFERENCE}", file=sys.stderr)
        return 1

    reference = parse_catalog(REFERENCE)
    reference_keys = [key for key, _ in reference]
    reference_values = dict(reference)
    failures: "list[str]" = []

    catalogs = sorted(
        p
        for p in I18N_DIR.glob("*.dart")
        if p.name not in {"i18n.dart", "i18n_keys.dart"}
    )
    if REFERENCE not in catalogs:
        catalogs.insert(0, REFERENCE)

    for path in catalogs:
        entries = parse_catalog(path)
        keys = [key for key, _ in entries]
        values = dict(entries)
        problems: "list[str]" = []

        if len(set(keys)) != len(keys):
            duplicates = sorted({k for k in keys if keys.count(k) > 1})
            problems.append(f"duplicate keys: {', '.join(duplicates)}")

        if path != REFERENCE:
            missing = [k for k in reference_keys if k not in values]
            extra = [k for k in keys if k not in reference_values]
            if missing:
                problems.append(f"missing {len(missing)}: {', '.join(missing)}")
            if extra:
                problems.append(f"extra {len(extra)}: {', '.join(extra)}")
            if not missing and not extra and keys != reference_keys:
                first = next(
                    (
                        i
                        for i, (a, b) in enumerate(zip(keys, reference_keys))
                        if a != b
                    ),
                    None,
                )
                problems.append(f"order differs from en_US (first at index {first})")

        empty = [key for key, value in entries if not value]
        if empty:
            problems.append(f"empty values: {', '.join(empty)}")

        seen: "dict[str, str]" = {}
        for key, value in entries:
            if len(value) < DUPLICATE_MIN_LENGTH:
                continue
            previous = seen.get(value)
            if previous is not None and previous != key:
                problems.append(f"'{key}' repeats the sentence of '{previous}'")
            seen.setdefault(value, key)

        status = "ok" if not problems else "FAIL"
        print(f"{path.name:12s} {len(entries):3d} keys  {status}")
        for problem in problems:
            print(f"    - {problem}")
        if problems:
            failures.append(path.name)

        if not args.no_advisory and path != REFERENCE:
            inherited = [
                key
                for key, value in entries
                if key not in INTENTIONALLY_UNTRANSLATED
                and reference_values.get(key) == value
            ]
            if inherited:
                print("    advisory: identical to en-US: " + ", ".join(inherited))

    expected = declared_keys()
    if expected:
        missing_consts = [k for k in expected if k not in reference_values]
        if missing_consts:
            print(
                "FAIL i18n_keys.dart declares keys missing from en_US: "
                + ", ".join(missing_consts)
            )
            failures.append("i18n_keys.dart")
        else:
            print(f"i18n_keys.dart {len(expected)} constants covered by en_US")

    if failures:
        print(f"\n{len(failures)} catalog(s) need work: {', '.join(failures)}")
        return 1
    print("\nAll catalogs structurally sound.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
