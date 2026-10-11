#!/usr/bin/env python3
"""Generates Owlet/Localizable.xcstrings from the translation table below.

The catalog is a generated file: keeping one table with all four languages side by side is the only
way to keep 200+ entries consistent, and a test asserts the checked-in catalog matches this table, so
an entry can never be edited in one place and forgotten in the other.

    python3 scripts/build-strings.py          # write the catalog
    python3 scripts/build-strings.py --check   # fail if the catalog is out of date

Source language is Simplified Chinese (see project.yml), so the keys are the Chinese strings exactly
as they appear in the code. Placeholders use Foundation's %lld / %@ for integers and objects.
"""
import argparse
import json
import pathlib
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "Owlet" / "Localizable.xcstrings"
SOURCE = "zh-Hans"
TARGETS = ["en", "zh-Hant", "ja"]

# key: (English, Traditional Chinese, Japanese). The key is the Simplified Chinese source string.
TABLE: dict[str, tuple[str, str, str]] = {
    # The app menu and sidebar.
    "翻译与润色": ("Translate & Polish", "翻譯與潤色", "翻訳と推敲"),
    "我的积累": ("My Collection", "我的累積", "マイコレクション"),
    "生词本": ("Notebook", "生詞本", "単語帳"),
    "历史记录": ("History", "歷史記錄", "履歴"),
    "关闭窗口": ("Close Window", "關閉視窗", "ウインドウを閉じる"),
    "打开 Owlet": ("Open Owlet", "打開 Owlet", "Owlet を開く"),
    "设置…": ("Settings…", "設定…", "設定…"),
    "退出 Owlet": ("Quit Owlet", "結束 Owlet", "Owlet を終了"),
    "剪切": ("Cut", "剪下", "切り取り"),
    "拷贝": ("Copy", "拷貝", "コピー"),
    "粘贴": ("Paste", "貼上", "ペースト"),
    "全选": ("Select All", "全選", "すべてを選択"),
    # The settings panes.
    "通用": ("General", "一般", "一般"),
    "语言": ("Languages", "語言", "言語"),
    "模型": ("Model", "模型", "モデル"),
    "快捷键": ("Shortcuts", "快速鍵", "ショートカット"),
    "调试": ("Debug", "除錯", "デバッグ"),
    # The interface language picker. A language names itself, so its own readers recognise it.
    "界面语言": ("Interface Language", "介面語言", "表示言語"),
    "跟随系统": ("Follow System", "跟隨系統", "システムに従う"),
    "简体中文": ("简体中文", "简体中文", "简体中文"),
    "繁體中文": ("繁體中文", "繁體中文", "繁體中文"),
    "English": ("English", "English", "English"),
    "日本語": ("日本語", "日本語", "日本語"),
    "改动在下次启动 Owlet 后生效。": (
        "Takes effect the next time Owlet starts.",
        "改動在下次啟動 Owlet 後生效。",
        "次回 Owlet の起動時から反映されます。",
    ),
}


def catalog() -> dict:
    strings = {}
    for key, (en, zh_hant, ja) in sorted(TABLE.items()):
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                SOURCE: {"stringUnit": {"state": "translated", "value": key}},
                "en": {"stringUnit": {"state": "translated", "value": en}},
                "zh-Hant": {"stringUnit": {"state": "translated", "value": zh_hant}},
                "ja": {"stringUnit": {"state": "translated", "value": ja}},
            },
        }
    return {"sourceLanguage": SOURCE, "strings": strings, "version": "1.0"}


def rendered() -> str:
    # Sorted keys and two-space indent keep the file diffable; ensure_ascii is off so the Chinese and
    # Japanese stay readable in review.
    return json.dumps(catalog(), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


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
        print(f"catalog is up to date ({len(TABLE)} entries)")
        return 0

    CATALOG.write_text(wanted, encoding="utf-8")
    print(f"wrote {CATALOG} ({len(TABLE)} entries, {len(TARGETS) + 1} languages each)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
