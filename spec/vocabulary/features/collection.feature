# English: collection.feature · 简体中文: collection.zh-CN.feature
Feature: Unified saving
  The user can deliberately save a word, phrase or whole sentence together with its context.

  Rule: Saving does not depend on study suggestions
    Scenario Outline: Manually pick content to save
      Given study suggestions are off
      And the user is viewing "<source>"
      When the user picks a "<content>" and saves it
      Then the entry is saved immediately without a form to fill in
      And the expression, language and source sentence context are kept
      Examples:
        | source | content |
        | source text | word |
        | translation result | phrase |
        | polish result | whole sentence |
        | history details | phrase |

    Scenario: Save a polished expression
      Given the user is viewing a polish result
      When the user saves the improved expression
      Then the entry keeps the before and after pair

    Scenario: Contextual meaning already available
      Given the content being saved already has a contextual meaning
      When the user saves it
      Then the meaning is saved with the entry

    Scenario: Meaning missing and filling it in fails
      Given the content the user selected by hand has no contextual meaning
      When filling in the meaning fails after the user saves it
      Then the saved expression and source sentence still exist
      And the user can retry filling in the meaning

  Rule: A repeated expression can append a context
    Scenario: The same English expression in a new source sentence
      Given the notebook already contains the English expression "follow up"
      When the user saves "follow up" from another source sentence and chooses to append the context
      Then the existing entry gains the new context
      And the old context is not overwritten

    Scenario: Identical expressions in different languages
      Given the notebook already contains the Chinese expression "手紙"
      When the user saves the Japanese expression "手紙"
      Then it is saved as an entry in a different language
      And the contexts of the two are not merged automatically

    Scenario: Submitting the same context again
      Given the current context of an expression is already saved
      When the user submits the same save again
      Then the same context is not appended twice

  Rule: Saving records the entry point and the app the source text came from
    Scenario Outline: Entry point
      When the user saves an expression through "<entry point>"
      Then the context's entry point is recorded as "<source>"
      Examples:
        | entry point | source |
        | selecting in the source text or result | selection |
        | checking it in the study area | study suggestion |
        | the study area in history details | history |

    Scenario: The source app travels with the flow
      Given the user selects text in the Mail app and triggers a translation
      When the user saves an expression from the study area
      Then the context's source app is the Mail app

    Scenario: Saving from history keeps the history's source app
      Given a history record whose source text came from Slack
      When the user saves an expression from that record's study area
      Then the context's source app is Slack

    Scenario: Manual input has no source app
      Given the user types text in the main window and translates it
      When the user saves an expression
      Then the context has no source app
