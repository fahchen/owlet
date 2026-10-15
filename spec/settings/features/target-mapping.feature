# English: target-mapping.feature · 简体中文: target-mapping.zh-CN.feature
Feature: Choose the translation target from the source language
  The translation target language is decided by the locally detected source language and the user's mapping; when nothing matches, the fallback target is used.

  Rule: The mapping table decides the translation target
    Scenario: Use the fallback target when the table is empty
      Given the user has not added any mapping
      And the fallback target is Simplified Chinese
      And the source text is "Could you send me the report?"
      When the user runs a translation
      Then the target language is Simplified Chinese

    Scenario: A mapping matches
      Given the user adds the mapping "English → Japanese"
      When the user translates English text
      Then the target language is Japanese
      And the result is in Japanese

    Scenario: Use the fallback target when the source language is not recognized
      Given the source text is too short or its language cannot be detected reliably
      When the user runs a translation
      Then the fallback target language is used

    Scenario: Use the fallback target when the source language is not listed
      Given the source text is French
      And the mapping table has no French row
      When the user runs a translation
      Then the fallback target language is used

    Scenario: One source language maps to one target only
      Given the user has added the mapping "English → Japanese"
      When the user adds the mapping "English → Chinese" for English
      Then English keeps only the target "Chinese"
      And there is no longer a duplicate English row

  Rule: The source language is detected locally before the request is sent
    Scenario: Detection does not change response validation
      Given local detection judged the source text to be English
      When the source language returned by the model differs from the local judgment
      Then the result is still valid as long as the returned target language matches the request

    Scenario: Mixed text takes the dominant language
      Given the source text is mostly Chinese with some English terms
      When the user runs a translation
      Then the source language is treated as Chinese
      And the target is chosen by the mapping for Chinese

  Rule: Translate and Replace reuses the same mapping
    Scenario: Resolves the same as a plain translation
      Given the mapping points English to Japanese
      When the user invokes Translate and Replace on an English selection
      Then the target language is also Japanese
      And the written-back content is the Japanese translation

  Rule: Polish ignores the mapping and keeps mixed languages
    Scenario: Polish does not show the target language control
      Given the user switches to Polish on the text processing page
      Then the target language control is not shown

    Scenario: Polish keeps the source language
      Given the mapping points English to Japanese
      And the source text is English
      When the user runs Polish
      Then the result is still English
      And the language does not change because of the mapping

    Scenario: Mixed text is not normalized
      Given the source text is Chinese with some English terms
      When the user runs Polish
      Then the English terms remain English
      And no fragment is translated or transliterated

  Rule: Toolbar automatic mode and manual override
    Scenario: Automatic by default
      Given the user has not chosen a target language manually
      When the user translates English text
      Then the target is decided by the mapping or the fallback
      And the control shows Automatic and the resolved target language

    Scenario: A manual choice overrides persistently
      Given the user explicitly chooses Japanese on the text processing page
      When the user translates English text
      Then the target language is Japanese
      When the user restarts the app and translates English text again
      Then the target language is still Japanese

    Scenario: Switching back to Automatic restores the mapping
      Given the user previously chose Japanese explicitly
      When the user switches the target language back to Automatic
      Then later translations again decide the target by the mapping or the fallback

  Rule: Native languages only affect study content
    Scenario: Placement and default
      Given the user opens the "Languages" tab in settings
      Then next to the mapping table there is a "Native Languages" multi-select, unset by default
      And the candidates are the languages the app is using, not every system language

    Scenario: Several native languages can be chosen
      Given the user knows both Simplified Chinese and English
      When the user sets both as native languages
      Then expressions in both languages are excluded from study content
      And expressions in other languages can still be suggested

    Scenario: Not part of the meaning language calculation
      Given the user sets the native language to Simplified Chinese
      And the mapping points English to Simplified Chinese
      When the user translates English into Simplified Chinese and saves an expression
      Then the meaning language is still this translation's target language, Simplified Chinese
      And the native language setting does not change the meaning language

    Scenario: Persistence
      Given the user sets the native language to Japanese
      When the user restarts the app
      Then the native language is still Japanese

    Scenario: A native language is removed from the language selection
      Given the user sets English as a native language
      When the user removes English on the "Languages" tab
      Then English is no longer in the native languages list either

  Rule: Settings persistence and migration
    Scenario: The mapping and fallback target persist
      Given the user adds a mapping and changes the fallback target
      When the user restarts the app
      Then the mapping and fallback target are unchanged

    Scenario: Carry over the old target language setting
      Given before this feature the user had saved the target language as Japanese
      When the user opens settings after upgrading
      Then the fallback target is Japanese
      And the mapping table is empty
