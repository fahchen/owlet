# English: panel-glass.feature · 简体中文: panel-glass.zh-CN.feature
Feature: Panel glass effect
  Scenario: Readability by default
    Given the user has not chosen a panel glass effect
    Then the glass effect in General settings is "Higher Contrast"

  Scenario: Switch the effect and keep the choice
    Given the user opens General settings
    When the user sets the glass effect to "More Transparent"
    Then the current panel's glass surface immediately becomes more transparent
    And the translating, error, result, and study states use the same choice
    And the choice is kept after a restart
    And the main window's appearance does not change

  Scenario: Glass intensity is decided by System Settings
    Given the user opens General settings
    Then the "Panel" group explains that Liquid Glass and its intensity are adjusted in "System Settings › Appearance"
    And the app's own choice only distinguishes two glass variants, "More Transparent" and "Higher Contrast"
    And the app offers no control that suggests it can adjust glass intensity itself
    And an entry to open "System Settings › Appearance" is provided
