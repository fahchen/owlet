# English: translation.feature · 简体中文: translation.zh-CN.feature
Feature: Translation
  The user can translate selected or typed text into the target language.

  Rule: Detect the source language automatically and remember the target language
    Scenario: Translate English for the first time
      Given the user has not set a target language
      And the source text is "Could you send me the report?"
      When the user runs Translate
      Then the result conveys a request to send the report, in Chinese
      And the source language is detected as English

    Scenario: Remember the switched target language
      Given the user switches the target language to Japanese
      When the user restarts the app and translates Chinese text
      Then the target language is still Japanese
      And the result is in Japanese and keeps the original meaning

  Rule: After a read failure, the user can still translate by entering text manually
    Scenario: Enter text manually
      Given there is no selected text that can be read
      And the floating toolbar has not expanded yet
      When the user invokes the Translate shortcut
      Then a compact read-failure notice with an Enter Text entry is shown
      And the full floating toolbar does not expand
      When the user chooses Enter Text
      Then the full window allows typing or pasting text
      When the user enters "お疲れさまです" and runs Translate
      Then the full window shows the translation in the target language

  Rule: With nothing selected, the focused field's full text can be used (off by default)
    Scenario: Focus is in an editable field and no text is selected
      Given the user has turned on "Use the whole text of the focused field when nothing is selected"
      And keyboard focus is in an editable field with no text selected
      And the field contains text
      When the user invokes the Translate or Polish shortcut
      Then the field's full text is used as the source text
      And no read-failure notice is shown and no Enter Text entry is offered
      When the user invokes the Translate and Replace shortcut
      And the translation is generated successfully
      Then the field's text is selected in full first, then the whole text is replaced with the translation
      And the field contains only the translation, with the source text not appended at the insertion point

    Scenario: Behavior is unchanged when the conditions are not met
      Given the user has turned on "Use the whole text of the focused field when nothing is selected"
      And the focused element is not editable, or the field has no text
      When the user invokes the Translate or Polish shortcut
      Then the behavior is exactly the same as with the setting off

  Rule: Plain translation does not write back directly
    Scenario: View and copy the translation
      Given the user has a translation from the plain Translate entry
      Then the original selection stays unchanged
      When the user copies the result
      Then the clipboard contains the translation

  Rule: Copying the result completes the interaction
    Scenario: Copy the translation in the panel
      Given the user has a translation in the panel
      When the user copies the result
      Then the clipboard contains the translation
      And the panel closes

  Rule: A failure must not be presented as success
    Scenario: The service rejects the request
      Given the translation service returns an authentication failure
      When the user runs Translate
      Then the user sees an understandable error and can retry after fixing the configuration
      And the source text stays unchanged

    Scenario: An older request finishes after a newer one
      Given the user starts a translation of text A
      And then starts a new translation of text B
      When the result for text A returns after the result for text B
      Then the current result still belongs to text B

  Rule: The translation preview aligns sentence by sentence
    Scenario: Translate several English sentences into Chinese
      Given the user chooses the Sentence by Sentence display
      And the source text contains several English sentences
      When the Chinese translation finishes
      Then each English sentence has its Chinese translation shown below it
      And a long sentence that wraps stays in the same aligned group
      And copy or replace uses only the Chinese translation

  Rule: The translation display preference is configurable and persistent
    Scenario: Separate panes by default
      Given the user has not changed the translation display
      When translation finishes
      Then the full source text and the full translation are shown separately
      And they are not interleaved sentence by sentence

    Scenario: Both arrangements show both sides at once
      Given the source text and the translation have both been generated
      When the content area is at least 600pt wide
      Then the source text and the translation sit side by side in the same glass card, separated by a divider and scrolling separately
      When the content area is narrower than 600pt
      Then the source text and the translation are stacked vertically and scroll separately

    Scenario: Specify the source language on the source side
      Given the mapping points English to Japanese
      And the source text is Japanese
      When the user sets the source language to English on the source side
      Then the target language is taken from the English row, which is Japanese
      And the request itself does not send the source language; the model still detects it

    Scenario: Switch to sentence by sentence
      Given the user already has a translation result
      When the user switches the display to Sentence by Sentence on the General page of settings
      Then the full window and the panel use the same display preference
      And the model is not requested again because the display changed
      And the Sentence by Sentence preference is kept after a restart

  Rule: The full window follows the Figma Translate / Polish artboard layout
    Scenario: Translate and polish layout
      Given the user opens the Translate & Polish page
      Then the left of the toolbar is an icon-only Translate / Polish segmented control, with the selected icon blue for Translate and green for Polish, followed by the current mode's title
      And when translating, the right side shows the source language, », and the target language; Polish shows only the source language
      And the language buttons size to the current option
      And the page has no run button, and the source placeholder hints ⌘↩
      And the source text and the result are in one glass card with a 34pt corner radius, with the Study and Copy buttons floating at the bottom right
      And processing text and errors are centered horizontally and vertically in the result column

  Scenario: Text containers use the system glass material
    When the source text, the translation, or the expanded study content is viewed
    Then the container uses the system Liquid Glass effect
    And body text keeps the system text style, with no hand-drawn blur, shadow or translucent fill

  Scenario: Study matches the panel
    When the user clicks Study after the result is ready
    Then the left column shows the result and the right column lists the study expressions
    And the Back button returns to the source text and the result
    And the source text and the result sit side by side when the content width reaches 600pt
