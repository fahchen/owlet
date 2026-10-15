# English: definition-language.feature · 简体中文: definition-language.zh-CN.feature
Feature: Meaning language
  The meanings the user gets are in the language they are practicing, not a fixed native language.

  Background:
    Given the target mapping is "English → Simplified Chinese" and "Simplified Chinese → English"
    And the fallback target is Simplified Chinese

  Rule: In translation, the meaning strictly uses this run's target language
    Scenario: Save an English expression while reading English
      Given the user translates a piece of English into Chinese
      When the user saves "follow up" from the source text
      Then the meaning is in Chinese

    Scenario: Save a Chinese expression while writing Chinese
      Given the user translates a piece of Chinese into English
      When the user saves "把问题收敛一下" from the source text
      Then the meaning is in English

    Scenario: Saving from the translation side still uses the target language
      Given the user translates a piece of Chinese into English
      When the user saves "follow up" from the translation
      Then the meaning is in English, not Chinese

  Rule: In polishing, the meaning language is the source language looked up in the target mapping
    Scenario: Polish English
      Given the user polishes a piece of English
      When the user expands the study area
      Then the recommendations and meanings are in Chinese

    Scenario: Polish Chinese
      Given the user polishes a piece of Chinese
      When the user expands the study area
      Then the recommendations and meanings are in English

    Scenario: The source language is not in the mapping
      Given the user polishes a piece of Japanese
      When the user expands the study area
      Then the recommendations and meanings use the fallback target language

  Rule: Generation and regeneration both use the current mapping, and stored meanings are not recomputed automatically
    Scenario: Regenerate with the current mapping
      Given the user saved a Chinese expression while translating "Chinese → English"
      And later changed the mapping to "Chinese → Japanese"
      When the user regenerates the entry's meaning in the notebook
      Then the meaning becomes Japanese

    Scenario: A stored meaning is not recomputed when settings change
      Given the user saved an entry with an English meaning
      And later changed the mapping to "Chinese → Japanese"
      When the user opens the notebook detail
      Then the entry still shows the original English meaning
      And the detail offers "regenerate with the current settings"
      And no request is made until it is clicked

    Scenario: Filling in a missing meaning uses the current mapping
      Given the user saved a Chinese expression while translating "Chinese → English", but its meaning has not been generated
      And later changed the mapping to "Chinese → Japanese"
      When the user clicks Fill In Meaning
      Then the meaning request uses Japanese

    Scenario: The entry records the actual language of the stored meaning
      Given an entry already has a meaning
      Then the meaning language recorded on the entry matches the actual language of that meaning

    Scenario: Save from a translation record in the history detail
      Given a history record translating English into Chinese
      When the user saves an expression from that record's study area
      Then the meaning is in Chinese

    Scenario: Save from a polish record in the history detail
      Given a history record polishing Chinese
      When the user saves an expression from that record's study area
      Then the meaning is in English

  Rule: Entries from before the upgrade are not backfilled
    Scenario: Old entries keep their meanings
      Given an entry saved before the upgrade has a Chinese meaning
      When the user opens the notebook after upgrading
      Then the entry's meaning is unchanged
      And its meaning language is recorded as Simplified Chinese
