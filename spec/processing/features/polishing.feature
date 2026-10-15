# English: polishing.feature · 简体中文: polishing.zh-CN.feature
Feature: Polishing
  The user can read the source text and an improved version of it.

  Rule: Keep the language and meaning and give one result
    Scenario: Fix English grammar
      Given the source text is "She go to work every day."
      When the user invokes the Polish shortcut
      Then the result is correct English that keeps the original meaning
      And the source text and the polished result are each shown once as plain text
      And no diff background color or strikethrough is used
      And no toggle for comparing changes is offered
      And no multiple style variants are offered
      And the original selection has not been replaced yet

    Scenario: Polish Japanese
      Given the source text is a piece of Japanese work communication
      When the user runs Polish
      Then the result is still Japanese
      And no facts or commitments absent from the source are added

  Rule: The source text and polished result do not depend on the study toggle
    Scenario: The polished result is available with study turned off
      Given the polish study toggle is off
      When polishing succeeds
      Then the plain source text and the polished result are shown
      And no study recommendations are generated automatically
      And the user can copy the result or choose to replace the original selection
