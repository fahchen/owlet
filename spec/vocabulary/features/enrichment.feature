# English: enrichment.feature · 简体中文: enrichment.zh-CN.feature
Feature: Filling in entry details on demand
  Saving costs the user as little waiting as possible; when they come back to a word, one click adds the reading and part of speech, and any single field can be refreshed on its own.

  Background:
    Given a model service is configured
    And the notebook already contains the English expression "bandwidth"

  Rule: Saving does not request the reading or part of speech
    Scenario: Open right after saving
      When the user opens the entry right after saving it
      Then the entry exists
      And the reading and part of speech are empty

  Rule: "Fill In Missing" fills only empty fields and never overwrites existing content
    Scenario: Add the reading and part of speech
      Given the entry has a meaning, no reading and no part of speech
      When the user runs "Fill In Missing"
      Then the reading and part of speech are filled in
      And the meaning stays as it was

    Scenario: Keep a value the user edited
      Given the user has changed the entry's reading to their own notation
      And the part of speech is empty
      When the user runs "Fill In Missing"
      Then only the part of speech is filled in
      And the reading is still the user's value

    Scenario: Unavailable when nothing is missing
      Given the entry already has a meaning, a reading and a part of speech
      Then "Fill In Missing" is unavailable

  Rule: Meaning, reading and part of speech each have their own "Regenerate", which overwrites only that field
    Scenario: Regenerate only the reading
      Given the entry has all three fields
      When the user runs "Regenerate" on the reading
      Then the reading is replaced by the model's result
      And the meaning and part of speech are unchanged

    Scenario: An edited part of speech is overwritten by regenerating
      Given the user has changed the part of speech to verb
      When the user runs "Regenerate" on the part of speech
      Then the part of speech is replaced by the model's result
      And no confirmation appears

  Rule: A failed fill or regeneration leaves existing content alone and can be retried
    Scenario: Service not configured
      Given no model service is configured
      When the user runs "Fill In Missing"
      Then the reason is shown
      And the entry is unchanged

    Scenario: Partial success
      Given the entry has no reading and no part of speech
      When "Fill In Missing" returns a reading but fails on the part of speech
      Then the reading is saved
      And the part of speech can be retried

  Rule: Whole-sentence entries have no reading or part of speech
    Scenario: A whole sentence only fills in the meaning
      Given the notebook already contains the whole sentence "I will follow up with the team tomorrow."
      When the user views the entry
      Then no reading or part of speech is shown
      And "Fill In Missing" only fills in the meaning

  Rule: The reading notation comes from the language's setting and is saved with the reading
    Scenario Outline: Default notation
      Given the user has not changed the reading notation settings
      And the notebook already contains the "<language>" expression "<expression>"
      When the user runs "Fill In Missing"
      Then the reading uses "<notation>"

      Examples:
        | language | expression   | notation |
        | English  | bandwidth    | IPA      |
        | Japanese | お疲れ様です | Kana     |
        | Chinese  | 收敛         | Pinyin   |
        | French   | bonjour      | IPA      |

    Scenario: Changing the setting does not backfill existing readings
      Given the notebook has a Japanese expression whose reading is in kana
      When the user changes the Japanese reading notation to romaji
      Then that entry's reading is still in kana
      And readings filled in for Japanese afterwards use romaji
