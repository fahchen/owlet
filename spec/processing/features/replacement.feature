# English: replacement.feature · 简体中文: replacement.zh-CN.feature
Feature: Replace the original selection
  The user can replace on demand, or trigger translate-and-replace in one step.

  Rule: A plain result is replaced only when the user chooses to
    Scenario: Manually replace with the polished result
      Given the user has a polished result
      And the source selection is in editable text
      When the user chooses Replace
      Then only the original selection is replaced with the polished result, once

  Rule: Translate and Replace needs no second confirmation
    Scenario: Write back right after translating
      Given the target language is Japanese
      And the user has selected editable Chinese text
      When the user invokes the Translate and Replace shortcut
      And the translation is generated successfully
      Then the original selection is replaced with the Japanese translation, once
      And the user does not need to click Replace or confirm again

    Scenario: Replace the whole field when the source is the focused field's full text
      Given the user has turned on "Use the whole text of the focused field when nothing is selected"
      And keyboard focus is in an editable field with no text selected
      And the field contains text
      When the user invokes the Translate and Replace shortcut
      And the translation is generated successfully
      Then the field's text is selected in full first, then the whole text is replaced with the translation
      And the field contains only the translation, with the source text not appended at the insertion point

    Scenario: No valid selection
      Given there is no valid selection
      And the floating toolbar has not expanded yet
      When the user invokes the Translate and Replace shortcut
      Then a compact notice with an inline Enter Text entry is shown
      And the full floating toolbar does not expand
      When the user chooses Enter Text
      Then text can be typed or pasted in the full window
      And a translation of manually entered text is not written back anywhere automatically

  Rule: Close the panel once write-back succeeds
    Scenario: Close after a successful write-back instead of staying to confirm
      Given the user has started Translate and Replace
      When the translation is written back to the original selection successfully
      Then the panel closes right away
      And no "written back" confirmation is shown

  Rule: If it cannot write back, it must not write anywhere else
    # Write-back no longer compares the source element, document and selection: once the panel takes focus,
    # most apps rebuild their accessibility tree, so the comparison always fails and replacement would never happen.
    # Instead, editability gates the entry, and the resulting text confirms whether the write landed.
    Scenario Outline: Write-back does not land
      Given the user has started Translate and Replace
      When "<situation>" happens before the translation returns
      Then no keystrokes are sent to any other place
      And the translation is kept, a notice says it could not be written back, and the result can be copied
      Examples:
        | situation |
        | the selection is not editable |
        | the owning app cannot be brought to the front |
        | the owning app has quit |

    Scenario: The paste landed nowhere
      Given the user has started Translate and Replace
      When the source element's text has not changed after the synthesized ⌘V
      Then a notice says it could not be written back, and the translation is kept for copying

    Scenario: Must not fall back to appending when select-all cannot be confirmed
      Given the user has turned on "Use the whole text of the focused field when nothing is selected"
      And the source text came from the focused field's full text and that field has no selection
      When select-all did not take effect (the element cannot be selected in full, or only part was selected)
      Then no paste keystroke is sent
      And a notice says it could not be written back, and the translation is kept for copying

    Scenario Outline: The operation loses its write-back eligibility
      Given the user has started Translate and Replace
      When this operation "<state>"
      Then this operation does not write back to the original selection
      Examples:
        | state |
        | failed to translate |
        | was cancelled but its response arrives later |
        | was superseded by a newer operation but its response arrives later |

    Scenario: The completion signal arrives twice
      Given this translation has already replaced the original selection
      When the same operation receives the completion signal again
      Then the original text is not modified again

  Rule: History does not keep write-back permission
    Scenario: View a result from history
      Given the user opens a past translation record
      When the user views the result in history
      Then the result can be copied
      And the record's selection cannot be reused for replacement
