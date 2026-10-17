#!/usr/bin/env python3
"""Reports interface strings that would show as Chinese in a translated interface.

Reads the compiled `en.lproj/Localizable.strings` from the built app — the table the running app
actually consults — and checks the Chinese string literals in the source against it. A literal that is
not a key there is shown verbatim, which is exactly the failure this catches.

Run after a build:  python3 scripts/check-i18n.py [path/to/Owlet.app]
"""
import codecs
import glob
import pathlib
import re
import sys

# Chinese literals that are data rather than interface: the two default prompts, and the examples and
# task text sent to the model, which stay in Chinese on purpose.
EXEMPT_FILES = {"DefaultPrompts.swift"}
EXEMPT_MARKERS = (
    "key items", "json object", "kind is one of", "Respond with", "Example json", "must be",
    "Explain the text", "Write meaning", "definition_language is", "从这次", "为下面这条",
    "补释义", "学习推荐", "查词 ·", "解释这段", "急剧上涨", "退一步重新审视",
    "在这句话中指", "动词", "原油価格", "跳ね上が",
    # The model's test sentence is data sent to the model, not interface text (ModelSettingsPane).
    "蒹葭蒼蒼",
)

LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
CJK = re.compile(r"[\u3400-\u9fff]")


def unescape(literal: str) -> str:
    """A Swift literal and a catalog key are compared as the strings they denote, so `\\n` is a
    newline on both sides rather than the two characters a source file shows."""
    return codecs.decode(literal, "unicode_escape")


def normalize(specifier: str) -> str:
    """A literal and a catalog key are the same string once every placeholder is one token."""
    specifier = unescape(specifier)
    specifier = re.sub(r"%(@|lld|ld|d|s|\.\df)", "\x00", specifier)
    # Swift interpolation, with parentheses balanced so a nested call does not end it early.
    out, i = [], 0
    while i < len(specifier):
        if specifier.startswith("\\(", i):
            depth, i = 1, i + 2
            while i < len(specifier) and depth:
                depth += specifier[i] == "("
                depth -= specifier[i] == ")"
                i += 1
            out.append("\x00")
        else:
            out.append(specifier[i])
            i += 1
    return "".join(out)


def keys_in(app: pathlib.Path, language: str) -> set[str]:
    path = app / f"Contents/Resources/{language}.lproj/Localizable.strings"
    if not path.exists():
        raise SystemExit(f"no {language} localization at {path}; build first")
    text = path.read_bytes().decode("utf-16")
    return {normalize(k) for k in re.findall(r"<key>(.*?)</key>", text, re.S)}


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    app = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if app is None:
        found = glob.glob(str(pathlib.Path.home() / "Library/Developer/Xcode/DerivedData/Owlet-*/Build/Products/*/Owlet.app"))
        if not found:
            raise SystemExit("no built Owlet.app found; build first or pass its path")
        app = pathlib.Path(sorted(found)[-1])

    missing: list[str] = []
    for language in ("en", "zh-Hant", "ja"):
        keys = keys_in(app, language)
        for file in sorted((root / "Owlet").rglob("*.swift")):
            if file.name in EXEMPT_FILES:
                continue
            for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
                stripped = line.lstrip()
                if stripped.startswith(("//", "///")):
                    continue
                # A literal handed to `String(localized:)` is a key by construction, and its pieces may
                # span lines; what is checked here is a literal the UI would show verbatim.
                if "String(localized:" in line or 'localized:' in line:
                    continue
                for literal in LITERAL.findall(line):
                    if not CJK.search(literal) or any(m in literal for m in EXEMPT_MARKERS):
                        continue
                    if normalize(literal) not in keys:
                        missing.append(f"{language} {file.name}:{number}  {literal[:70]!r}")

    if missing:
        print(f"{len(missing)} interface strings would show as Chinese:")
        for line in missing:
            print(" ", line)
        return 1
    print("every interface string is translated in all three languages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
