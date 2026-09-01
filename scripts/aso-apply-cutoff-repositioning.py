#!/usr/bin/env python3
"""Reposition every localized listing around the personal cutoff.

Apple rejected 1.0 under Guideline 4.3. The listing led with a bedtime
forecast, which every app in the category also ships, and buried the one
output that is derived from the individual's own sleep record. This script
rewrites the parts of each localized listing that carry that positioning, and
the two lines that would otherwise still sell the cutoff as a paid feature
after it was made free.

Every localized `description.txt` shares the 40-line shape of the en-US file
the set was written from, so the lines are addressed by index rather than by
matching native prose:

     1  hook                  <- rewritten, now leads with the cutoff
     3  intro                    kept
    19  body section heading     kept, already describes the cutoff
    27  free heading             kept
    29  what is free          <- rewritten, the cutoff joins it
    31  what Caffeine+ adds   <- rewritten, the cutoff leaves it

`subtitle`, `keywords`, `promotional_text` and `release_notes` are replaced
outright. The release notes were English in all 49 non-en-US storefronts.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
STRINGS = Path(__file__).resolve().parent / "aso-cutoff-strings.json"

#: Locales whose script carries a word in one or two characters. The 24
#: character subtitle floor would only buy filler there, so they keep Apple's
#: ceiling alone. `asc-readiness.py` encodes the same exception.
DENSE_SCRIPT_LOCALES = {"ja", "ko", "zh-Hans", "zh-Hant"}

HOOK_LINE = 1
FREE_LINE = 29
PLUS_LINE = 31
EXPECTED_LINES = 40


def apply_locale(locale: str, strings: dict[str, str]) -> list[str]:
    """Rewrite one locale in place. Returns the problems found, if any."""
    problems: list[str] = []
    directory = META / locale
    if not directory.is_dir():
        return [f"{locale}: no metadata directory"]

    description_path = directory / "description.txt"
    lines = description_path.read_text().split("\n")
    # The trailing newline leaves an empty final element.
    body = lines[:-1] if lines and lines[-1] == "" else lines
    if len(body) != EXPECTED_LINES:
        return [f"{locale}: description is {len(body)} lines, expected {EXPECTED_LINES}"]

    body[HOOK_LINE - 1] = strings["hook"]
    body[FREE_LINE - 1] = strings["free"]
    body[PLUS_LINE - 1] = strings["plus"]
    description_path.write_text("\n".join(body) + "\n")

    (directory / "subtitle.txt").write_text(strings["subtitle"])
    (directory / "keywords.txt").write_text(strings["keywords"])
    (directory / "promotional_text.txt").write_text(strings["promotional_text"])
    (directory / "release_notes.txt").write_text(strings["release_notes"].rstrip("\n") + "\n")

    floor = 10 if locale in DENSE_SCRIPT_LOCALES else 24
    subtitle_length = len(strings["subtitle"])
    if not floor <= subtitle_length <= 30:
        problems.append(f"{locale}: subtitle is {subtitle_length} chars, want {floor}-30")
    keyword_length = len(strings["keywords"])
    keyword_floor = 0 if locale in DENSE_SCRIPT_LOCALES else 94
    if not keyword_floor <= keyword_length <= 100:
        problems.append(f"{locale}: keywords are {keyword_length} chars, want {keyword_floor}-100")
    promotional_length = len(strings["promotional_text"])
    if promotional_length > 170:
        problems.append(f"{locale}: promotional text is {promotional_length} chars, max 170")
    return problems


def main() -> int:
    table = json.loads(STRINGS.read_text())
    problems: list[str] = []
    for locale in sorted(table):
        problems.extend(apply_locale(locale, table[locale]))
    print(f"applied {len(table)} locales")
    for problem in problems:
        print(f"  {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
