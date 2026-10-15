# English: focus.feature · 简体中文: focus.zh-CN.feature
Feature: Native window input focus

  Scenario: Clicking outside the input area ends editing
    Given a text input in the main window or the settings window is being edited
    When I click empty space or another control outside the input area
    Then the current input ends editing and the original click still responds normally
    And text selection and scrolling inside the input area are unaffected
    And other windows and the floating panel are unaffected

Rule: Opening settings from the menu

  Scenario: A settings window behind other windows comes to the front
    Given the settings window is already open
    And it is covered by another window
    When I click "Settings…" again in the menu bar menu
    Then the settings window comes to the front and receives focus
    And the menu bar menu, the panel's settings button, and the prompt settings entry behave the same
