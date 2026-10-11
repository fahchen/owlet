#!/usr/bin/env python3
"""Generates Owlet/Localizable.xcstrings from strings/translations.json.

The interface's source language is English: a key *is* the English text, and every other language —
Simplified Chinese, Traditional Chinese, Japanese — lives in the catalog as a translation. That keeps
Chinese out of the Swift sources: the only places it is written are this data file and the catalog
generated from it.

    python3 scripts/build-strings.py          # write the catalog
    python3 scripts/build-strings.py --check   # fail when the catalog is out of date
"""
import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Owlet" / "Localizable.xcstrings"
TRANSLATIONS = ROOT / "strings" / "translations.json"
SOURCE = "en"
TARGETS = ["zh-Hans", "zh-Hant", "ja"]


def load() -> dict[str, dict[str, str]]:
    entries = json.loads(TRANSLATIONS.read_text(encoding="utf-8"))
    if not isinstance(entries, dict) or not entries:
        raise SystemExit(f"{TRANSLATIONS} must hold a non-empty object")
    return entries


def catalog(entries: dict[str, dict[str, str]]) -> dict:
    strings = {}
    for key, translations in sorted(entries.items()):
        localizations = {SOURCE: {"stringUnit": {"state": "translated", "value": key}}}
        for language in TARGETS:
            value = translations.get(language)
            if value is None:
                raise SystemExit(f"{key!r} has no {language} translation")
            localizations[language] = {"stringUnit": {"state": "translated", "value": value}}
        strings[key] = {"extractionState": "manual", "localizations": localizations}
    return {"sourceLanguage": SOURCE, "strings": strings, "version": "1.0"}


def rendered() -> str:
    # Sorted keys and two-space indent keep the file diffable; ensure_ascii is off so the Chinese and
    # Japanese stay readable in review.
    return json.dumps(catalog(load()), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail when the catalog is out of date")
    args = parser.parse_args()

    wanted = rendered()
    if args.check:
        current = CATALOG.read_text(encoding="utf-8") if CATALOG.exists() else ""
        if current != wanted:
            print("Localizable.xcstrings is out of date; run scripts/build-strings.py", file=sys.stderr)
            return 1
        print(f"catalog is up to date ({len(load())} entries)")
        return 0

    CATALOG.write_text(wanted, encoding="utf-8")
    print(f"wrote {CATALOG} ({len(load())} entries, {len(TARGETS) + 1} languages each)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
