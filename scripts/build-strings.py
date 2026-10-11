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
    # Model failures and the contract. These reach the panel, the settings window and the notebook, so
    # they are translated even though the prompts they come from are not.
    "网络错误：%@": ("Network error: %@", "網路錯誤：%@", "ネットワークエラー：%@"),
    "认证失败，请检查 API Key。": (
        "Authentication failed. Check the API key.",
        "認證失敗，請檢查 API Key。",
        "認証に失敗しました。API Key を確認してください。",
    ),
    "服务返回 HTTP %lld。": ("The service returned HTTP %lld.", "服務傳回 HTTP %lld。", "サービスが HTTP %lld を返しました。"),
    "服务返回了空内容。": ("The service returned empty content.", "服務傳回空內容。", "サービスが空の内容を返しました。"),
    "返回的结构不符合约定：字段缺失、类型不对或内容为空。": (
        "The reply does not match the agreed structure: a missing field, a wrong type, or empty content.",
        "回傳的結構不符合約定：欄位缺失、型別不對或內容為空。",
        "返された構造が約束と一致しません：項目の欠落、型の不一致、または内容が空です。",
    ),
    "返回的原文与提交的内容不一致，配对无法信任。": (
        "The returned source does not reassemble into what was submitted, so the pairing cannot be trusted.",
        "回傳的原文與提交的內容不一致，配對無法信任。",
        "返された原文が送信した内容と一致しないため、対応関係を信頼できません。",
    ),
    "返回的目标语言是 %@，与请求的 %@ 不一致。": (
        "The reply is in %@, which does not match the requested %@.",
        "回傳的目標語言是 %@，與請求的 %@ 不一致。",
        "返された言語は %@ で、要求した %@ と一致しません。",
    ),
    "结果过长被截断。": ("The result was cut off for being too long.", "結果過長被截斷。", "結果が長すぎて打ち切られました。"),
    "服务拒绝处理这段文本。": (
        "The service refused to process this text.",
        "服務拒絕處理這段文字。",
        "サービスがこのテキストの処理を拒否しました。",
    ),
    "（请求体不可读）": ("(the request body is unreadable)", "（請求內容無法讀取）", "（リクエスト本文を読めません）"),
    # The floating panel and the processing page.
    "取消处理": ("Cancel", "取消處理", "キャンセル"),
    "关闭浮窗": ("Close Panel", "關閉浮動視窗", "パネルを閉じる"),
    "关闭": ("Close", "關閉", "閉じる"),
    "设置": ("Settings", "設定", "設定"),
    "返回": ("Back", "返回", "戻る"),
    "返回结果": ("Back to Result", "返回結果", "結果に戻る"),
    "学习": ("Study", "學習", "学習"),
    "学习表达": ("Study Expressions", "學習表達", "学習表現"),
    "复制": ("Copy", "拷貝", "コピー"),
    "快捷操作": ("Shortcuts", "快速操作", "ショートカット"),
    "替换原选区": ("Replace Selection", "取代原選取範圍", "選択範囲を置換"),
    "原文": ("Source", "原文", "原文"),
    "收起原文": ("Hide Source", "收合原文", "原文を隠す"),
    "编辑原文": ("Edit Source", "編輯原文", "原文を編集"),
    "正在生成结果": ("Generating the result", "正在產生結果", "結果を生成しています"),
    "正在整理值得学习的表达…": (
        "Finding useful expressions…",
        "正在整理值得學習的表達…",
        "学習に役立つ表現を探しています…",
    ),
    "重试": ("Retry", "重試", "再試行"),
    "这次没有额外推荐。": ("Nothing more to suggest.", "這次沒有額外推薦。", "今回は追加の提案はありません。"),
    "已收藏": ("Saved", "已收藏", "保存済み"),
    "未收藏": ("Not saved", "未收藏", "未保存"),
    "取消收藏": ("Remove from Notebook", "取消收藏", "単語帳から削除"),
    "加入生词本": ("Add to Notebook", "加入生詞本", "単語帳に追加"),
    "处理方式": ("Operation", "處理方式", "処理方法"),
    "翻译": ("Translate", "翻譯", "翻訳"),
    "润色": ("Polish", "潤色", "推敲"),
    # Panel notices and their recovery entries.
    "需要选区读取权限": (
        "Needs permission to read the selection",
        "需要選取範圍讀取權限",
        "選択範囲の読み取り権限が必要です",
    ),
    "未能读取到文字": ("Could not read any text", "未能讀取到文字", "テキストを読み取れませんでした"),
    "模型服务未配置": ("The model service is not configured", "模型服務未設定", "モデルサービスが未設定です"),
    "返回格式错误，请检查提示词": (
        "The reply's format is wrong. Check the prompt.",
        "回傳格式錯誤，請檢查提示詞",
        "返答の形式が正しくありません。プロンプトを確認してください。",
    ),
    "连接失败，请检查模型服务": (
        "Connection failed. Check the model service.",
        "連線失敗，請檢查模型服務",
        "接続に失敗しました。モデルサービスを確認してください。",
    ),
    "未能写回原应用": ("Could not write back to the other app", "未能寫回原應用程式", "元のアプリに書き戻せませんでした"),
    "原选区不可编辑": ("The selection cannot be edited", "原選取範圍不可編輯", "選択範囲は編集できません"),
    "已取消处理": ("Cancelled", "已取消處理", "キャンセルしました"),
    "权限设置": ("Permission Settings", "權限設定", "権限設定"),
    "手动输入": ("Enter Text", "手動輸入", "手入力"),
    "配置服务": ("Configure Service", "設定服務", "サービスを設定"),
    "提示词设置": ("Prompt Settings", "提示詞設定", "プロンプト設定"),
    "服务设置": ("Service Settings", "服務設定", "サービス設定"),
    "复制结果": ("Copy Result", "拷貝結果", "結果をコピー"),
    "重新处理": ("Try Again", "重新處理", "やり直す"),
    # Composed at runtime: the operation's own name is filled in.
    "%@中…": ("%@…", "%@中…", "%@中…"),
    "输入或粘贴文字，⌘↩ %@": (
        "Type or paste text, ⌘↩ %@",
        "輸入或貼上文字，⌘↩ %@",
        "テキストを入力またはペースト、⌘↩ %@",
    ),
    "重新%@": ("Run %@ again", "重新%@", "%@をやり直す"),
    "%@文本": ("%@ Text", "%@文字", "%@テキスト"),
    "%@模式": ("%@ Mode", "%@模式", "%@モード"),
    "%@并替换": ("%@ and Replace", "%@並取代", "%@して置換"),
    "%@ System Prompt": ("%@ System Prompt", "%@ System Prompt", "%@ System Prompt"),
    # The notebook and history.
    "%lld 个表达": ("%lld expressions", "%lld 個表達", "%lld 件の表現"),
    "搜索表达或释义": ("Search expressions or meanings", "搜尋表達或釋義", "表現または意味を検索"),
    "删除所选 %lld 个表达？": (
        "Delete the %lld selected expressions?",
        "刪除所選 %lld 個表達？",
        "選択した %lld 件の表現を削除しますか？",
    ),
    "删除": ("Delete", "刪除", "削除"),
    "取消": ("Cancel", "取消", "キャンセル"),
    "操作失败": ("Operation failed", "操作失敗", "操作に失敗しました"),
    "好": ("OK", "好", "OK"),
    "尚无中文释义": ("No meaning yet", "尚無中文釋義", "意味はまだありません"),
    "%@ · %lld 个语境": ("%@ · %lld contexts", "%@ · %lld 個語境", "%@ · %lld 件の文脈"),
    "%@ · %lld 个语境 · 收藏于 %@": (
        "%@ · %lld contexts · saved %@",
        "%@ · %lld 個語境 · 收藏於 %@",
        "%@ · %lld 件の文脈 · %@ に保存",
    ),
    "已选择 %lld 个表达": ("%lld expressions selected", "已選擇 %lld 個表達", "%lld 件の表現を選択中"),
    "可使用工具栏删除所选内容。": (
        "Use the toolbar to delete the selection.",
        "可使用工具列刪除所選內容。",
        "ツールバーから選択項目を削除できます。",
    ),
    "选择一个表达": ("Select an expression", "選擇一個表達", "表現を選択してください"),
    "在左侧列表中选择内容以查看详情。": (
        "Select something in the list to see its details.",
        "在左側列表中選擇內容以查看詳細資訊。",
        "左のリストから項目を選ぶと詳細が表示されます。",
    ),
    "筛选语言": ("Filter by Language", "篩選語言", "言語で絞り込む"),
    "全部语言": ("All Languages", "全部語言", "すべての言語"),
    "上一条": ("Previous", "上一筆", "前へ"),
    "下一条": ("Next", "下一筆", "次へ"),
    "删除所选内容": ("Delete Selected", "刪除所選內容", "選択項目を削除"),
    "生词本为空": ("The notebook is empty", "生詞本為空", "単語帳は空です"),
    "无匹配结果": ("No Matches", "無相符結果", "一致する項目がありません"),
    "在学习区选择表达，即可加入生词本。": (
        "Pick an expression in the study list to add it to the notebook.",
        "在學習區選擇表達，即可加入生詞本。",
        "学習リストで表現を選ぶと単語帳に追加できます。",
    ),
    "试试其他搜索词或筛选条件。": (
        "Try another search or filter.",
        "試試其他搜尋詞或篩選條件。",
        "別の検索語や絞り込み条件をお試しください。",
    ),
    "前往翻译": ("Go to Translate", "前往翻譯", "翻訳へ移動"),
    "清除筛选": ("Clear Filters", "清除篩選", "絞り込みを解除"),
    "表达": ("Expression", "表達", "表現"),
    "释义": ("Meaning", "釋義", "意味"),
    "原句语境": ("Source Sentence", "原句語境", "原句の文脈"),
    "复制表达": ("Copy Expression", "拷貝表達", "表現をコピー"),
    "正在补充中文释义…": ("Filling in the meaning…", "正在補充中文釋義…", "意味を取得しています…"),
    "补充中文释义": ("Fill In Meaning", "補充中文釋義", "意味を取得"),
    "润色前": ("Before Polish", "潤色前", "推敲前"),
    "润色后": ("After Polish", "潤色後", "推敲後"),
    "没有可收藏的内容": ("There is nothing to save", "沒有可收藏的內容", "保存できる内容がありません"),
    "同语言下已存在相同的表达": (
        "An expression with the same text already exists in this language",
        "同語言下已存在相同的表達",
        "同じ言語に同じ表現がすでにあります",
    ),
    "生词本.json": ("Notebook.json", "生詞本.json", "単語帳.json"),
    # History.
    "%lld 条记录": ("%lld records", "%lld 筆記錄", "%lld 件の記録"),
    "搜索原文或结果": ("Search source or result", "搜尋原文或結果", "原文または結果を検索"),
    "历史保存失败：%@": ("Could not save history: %@", "歷史儲存失敗：%@", "履歴を保存できませんでした：%@"),
    "关闭提示": ("Dismiss", "關閉提示", "閉じる"),
    "删除所选 %lld 条历史记录？": (
        "Delete the %lld selected records?",
        "刪除所選 %lld 筆歷史記錄？",
        "選択した %lld 件の履歴を削除しますか？",
    ),
    "生词本中的表达不受影响。": (
        "Expressions in the notebook are not affected.",
        "生詞本中的表達不受影響。",
        "単語帳の表現には影響しません。",
    ),
    "已选择 %lld 条历史记录": ("%lld records selected", "已選擇 %lld 筆歷史記錄", "%lld 件の記録を選択中"),
    "选择一个记录": ("Select a record", "選擇一筆記錄", "記録を選択してください"),
    "筛选类型": ("Filter by Type", "篩選類型", "種類で絞り込む"),
    "全部类型": ("All Types", "全部類型", "すべての種類"),
    "暂无历史记录": ("No History Yet", "暫無歷史記錄", "履歴はまだありません"),
    "成功的翻译与润色会自动记录在这里。": (
        "Translations and polishes you run are recorded here automatically.",
        "成功的翻譯與潤色會自動記錄在這裡。",
        "実行した翻訳と推敲はここに自動で記録されます。",
    ),
    "今天 %@": ("Today %@", "今天 %@", "今日 %@"),
    "昨天 %@": ("Yesterday %@", "昨天 %@", "昨日 %@"),
    # Settings: model, languages, sounds, targets, prompts, debug.
    "服务商": ("Provider", "服務商", "プロバイダ"),
    "服务": ("Service", "服務", "サービス"),
    "API Key 存在钥匙串里；离开输入框后生效。": (
        "The API key is kept in the keychain, and applies when the field loses focus.",
        "API Key 存在鑰匙圈裡；離開輸入框後生效。",
        "API Key はキーチェーンに保存され、入力欄から離れたときに反映されます。",
    ),
    "思考强度": ("Reasoning Effort", "思考強度", "推論の強度"),
    "模型名称": ("Model Name", "模型名稱", "モデル名"),
    "填写服务商提供的模型名称": (
        "Enter the model name the provider gives you",
        "填寫服務商提供的模型名稱",
        "プロバイダが指定するモデル名を入力してください",
    ),
    "移除%@": ("Remove %@", "移除%@", "%@を削除"),
    "添加语言": ("Add Language", "新增語言", "言語を追加"),
    "选择要添加的语言": ("Choose a language to add", "選擇要新增的語言", "追加する言語を選択"),
    "只有这里选中的语言会出现在目标语言、兜底目标和映射表里；至少保留一种。": (
        "Only the languages chosen here appear in the target, the fallback and the mapping; keep at least one.",
        "只有這裡選中的語言會出現在目標語言、兜底目標和映射表裡；至少保留一種。",
        "ここで選んだ言語だけが翻訳先・既定の翻訳先・対応表に表示されます。少なくとも 1 つ必要です。",
    ),
    "假名": ("Kana", "假名", "かな"),
    "罗马字": ("Romaji", "羅馬字", "ローマ字"),
    "拼音": ("Pinyin", "拼音", "ピンイン"),
    "注音": ("Zhuyin", "注音", "注音符号"),
    "读音体系": ("Reading Notation", "讀音體系", "読みの表記"),
    "用于生词本补充读音与阅读查词；改动只影响之后的请求。": (
        "Used when filling in a reading or looking a word up while reading; a change affects later requests only.",
        "用於生詞本補充讀音與閱讀查詞；改動只影響之後的請求。",
        "単語帳の読みの補完と閲覧中の調べ物に使われます。変更は今後のリクエストにのみ影響します。",
    ),
    "兜底目标": ("Fallback Target", "兜底目標", "既定の翻訳先"),
    "添加映射": ("Add Mapping", "新增映射", "対応を追加"),
    "翻译目标语言": ("Translation Target", "翻譯目標語言", "翻訳先の言語"),
    "源语言由原文自动识别。未识别出源语言、或源语言没有对应行时使用兜底目标；一个源语言只保留一条映射。": (
        "The source is detected from the text. The fallback is used when it cannot be detected or has no row; one source keeps one mapping.",
        "源語言由原文自動識別。未識別出源語言、或源語言沒有對應列時使用兜底目標；一個源語言只保留一條映射。",
        "原文から言語を自動判定します。判定できない場合や対応する行がない場合は既定の翻訳先を使います。1 つの言語につき対応は 1 つです。",
    ),
    "源语言": ("Source Language", "源語言", "元の言語"),
    "目标语言": ("Target Language", "目標語言", "翻訳先の言語"),
    "删除%@的映射": ("Remove the mapping for %@", "刪除%@的映射", "%@ の対応を削除"),
    "自动（%@）": ("Automatic (%@)", "自動（%@）", "自動（%@）"),
    "自动（未识别）": ("Automatic (not detected)", "自動（未識別）", "自動（未判定）"),
    "自动（服务商默认）": (
        "Automatic (the provider's default)",
        "自動（服務商預設）",
        "自動（プロバイダの既定）",
    ),
    "关闭": ("Off", "關閉", "オフ"),
    "低": ("Low", "低", "低"),
    "中": ("Medium", "中", "中"),
    "高": ("High", "高", "高"),
    "最高": ("Highest", "最高", "最高"),
    "原文／译文分区": ("Source / Result Sections", "原文／譯文分區", "原文／訳文の分割表示"),
    "逐句对照": ("Sentence by Sentence", "逐句對照", "文ごとの対訳"),
    "固定位置": ("Fixed Position", "固定位置", "固定位置"),
    "跟随选区": ("Follow the Selection", "跟隨選取範圍", "選択範囲に追従"),
    "内容不能为空；这次改动没有生效。": (
        "The content cannot be empty; this change was not applied.",
        "內容不能為空；這次改動沒有生效。",
        "内容を空にはできません。この変更は反映されませんでした。",
    ),
    "恢复默认": ("Restore Default", "恢復預設", "既定に戻す"),
    "默认": ("Default", "預設", "既定"),
    "还没有记录": ("Nothing recorded yet", "還沒有記錄", "まだ記録がありません"),
    "发一次翻译或润色后会出现在这里。": (
        "Run a translation or a polish and it appears here.",
        "發一次翻譯或潤色後會出現在這裡。",
        "翻訳または推敲を実行するとここに表示されます。",
    ),
    "提交原文": ("Submitted Text", "提交原文", "送信した原文"),
    "模型原始返回": ("Model Raw Reply", "模型原始回傳", "モデルの生の返答"),
    "请求体": ("Request Body", "請求內容", "リクエスト本文"),
    "复制这条记录": ("Copy This Record", "拷貝這筆記錄", "この記録をコピー"),
    # Language names. The system names a language in the *system's* language, which is not what a
    # reader of the interface language expects, so the languages this app deals with are translated.
    "简体中文": ("Simplified Chinese", "簡體中文", "簡体字中国語"),
    "繁體中文": ("Traditional Chinese", "繁體中文", "繁体字中国語"),
    "英语": ("English", "英語", "英語"),
    "日语": ("Japanese", "日語", "日本語"),
    "韩语": ("Korean", "韓語", "韓国語"),
    "法语": ("French", "法語", "フランス語"),
    "德语": ("German", "德語", "ドイツ語"),
    "西班牙语": ("Spanish", "西班牙語", "スペイン語"),
    "俄语": ("Russian", "俄語", "ロシア語"),
    "清除%@快捷键": ("Clear the %@ shortcut", "清除%@快速鍵", "%@ のショートカットを消去"),
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
