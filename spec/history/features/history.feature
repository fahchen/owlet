# English: history.feature · 简体中文: history.zh-CN.feature
Feature: Operation history
  The user can find the source text and results of translations and polishes again.

  Rule: Successfully generated results are saved automatically
    Scenario Outline: Save the result
      Given the user runs "<action>"
      When the result is generated successfully
      Then history saves the source text, result, language, time and type "<type>"
      And it can still be viewed after a restart
      Examples:
        | action | type |
        | Translate | Translate |
        | Polish | Polish |
        | Translate and Replace | Translate |

    Scenario: The translation succeeds but replacement fails
      Given Translate and Replace has generated a translation
      When replacement fails because writing back to the original app failed
      Then the translation history still keeps the source text and the translation

    Scenario: The request fails
      When a translate or polish request fails or is cancelled
      Then it is not saved as successful history

  Rule: History can be searched and reused
    Scenario: Combine filtering and search
      Given the user has several translate and polish records
      When the user filters by Polish and searches for a word in the source text
      Then only the matching polish records are shown
      And a record's detail can be opened to start a study request

  Rule: History is cleaned up by the user and never expires automatically
    Scenario: Delete one history record
      Given the user has two history records
      When the user deletes one of them and restarts
      Then only the other record is kept

    Scenario: Cancel clearing
      Given the user has history records
      When the user starts clearing but cancels the confirmation
      Then the history records stay unchanged

    Scenario: Confirm clearing
      Given the user has history records
      When the user confirms clearing all history
      Then the history list is empty

    Scenario: Long-term retention
      Given the user has not deleted existing history
      When the user reopens history later
      Then no record is deleted automatically because of its age

  Rule: The history detail adds to the notebook through the study flow
    Scenario: Study an existing history record
      Given the user selects a history record
      When the user clicks the Study button at the bottom right of the detail
      Then the source text collapses, the result stays on top, and the study list expands below and is requested on demand
      And clicking an entry toggles saving immediately
      And the whole source text is not saved as a single notebook entry

    Scenario: Split view and toolbar
      Given the user opens History
      Then the list and the detail scroll separately, and the toolbar is translucent
      And the filter is on the left of the toolbar, search is at the far right, and delete is on the right
      And the bottom right of the detail offers the Study and Copy Result buttons
      And no edit or export button is offered

  Scenario: The count scrolls with the list
    When the history list is viewed
    Then no duplicate History window title is shown
    And the record count scrolls with the content as a gray, non-selectable label in the first row of the list

  Scenario: Browse adjacent records and empty states
    When the list is viewed
    Then the count is centered in the scrolling space above the first item, without adding top safe-area padding
    And the Previous and Next toolbar buttons move in the current filter order and are disabled at the ends
    And an empty library offers a way to Translate, and no matching results offers Clear Filters

  Scenario: Multi-select deletion and a separate navigation group
    When the user selects several records in the list with Command or Shift
    Then the selected count is confirmed before deletion, and only the selected records are deleted
    And Study and Previous / Next are unavailable while several records are selected
    And Previous / Next sit in a separate toolbar group on the right

  Scenario: Single-level filter
    When the filter menu is opened
    Then All Types, Translate and Polish are shown directly, with no submenu

  Scenario: Notes-style toolbar search
    When History is viewed
    Then the system search sits at the far right of the toolbar, separated from the navigation and content action groups
