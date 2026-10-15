# English: notebook.feature · 简体中文: notebook.zh-CN.feature
Feature: Notebook management
  The user can find, view and delete notebook content.

  Rule: The notebook can be viewed persistently
    Scenario: View after a restart
      Given the user has saved a Japanese phrase
      When the user restarts the app and opens the notebook
      Then the phrase and its context can still be viewed

    Scenario: Search and language filter
      Given the notebook contains English and Japanese entries
      When the user selects the Japanese filter and types a search term
      Then only Japanese entries matching the search are shown

    Scenario: Language, tag and starred filters combine
      Given the notebook contains several languages, several tags and some starred entries
      When the user selects English, the tag "work" and checks starred only
      Then only entries meeting all three are shown

    Scenario: Multiple tags match any of them
      Given the notebook has entries tagged "work" and entries tagged "email"
      When the user selects both the "work" and "email" tags
      Then entries with either tag are shown

    Scenario: Filter by source app
      Given the notebook has English entries met in Slack and in the Mail app
      When the user selects English and chooses Slack as the source app
      Then only English entries met in Slack are shown

    Scenario: Delete an entry
      Given the user has saved an entry
      When the user deletes the entry and restarts the app
      Then the notebook no longer contains the entry

  Rule: Saved items are not deleted with history
    Scenario: Clear the source history
      Given the user saved an expression from a history record
      When the user clears all history
      Then the saved item and its source sentence context can still be viewed
      And the context still shows its entry point and source app
      But it can no longer jump to that history record

  Rule: The notebook uses native split view management
    Scenario: The list and the details scroll independently
      Given the notebook has enough entries and long contexts
      When the user selects an entry and scrolls the details
      Then the list keeps its own scroll position
      And in the toolbar, search and filter form one group and delete is an action on the right
      And there are no export or copy buttons

  Scenario: The count scrolls with the expression list
    When the user views the notebook
    Then the notebook window title is not repeated
    And the expression count is a grey, non-selectable label in the list's first row that scrolls with the content

  Scenario: Browsing adjacent entries and empty states
    When the user views the list
    Then the count is centred in the scroll margin above the first item, without adding extra top safe-area margin
    And the toolbar's previous and next switch entries in the current filter order and are disabled at the ends
    And an empty notebook offers to go to Translate, and no matches offers to clear the filters

  Scenario: Multi-select delete and a separate navigation group
    When the user selects several expressions in the list with Command or Shift
    Then deleting first confirms the selected count and deletes only the selected expressions and their contexts
    And previous and next are unavailable during multi-select
    And previous and next sit in their own toolbar group on the right

  Scenario: Single-level language filter
    When the user opens the filter menu
    Then all languages and each language are shown directly, with no submenu

  Scenario: Notes-style toolbar search
    When the user views the notebook
    Then the system search field sits at the far right of the toolbar, separate from the navigation and content action groups
