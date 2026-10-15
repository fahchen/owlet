# English: shortcuts.feature · 简体中文: shortcuts.zh-CN.feature
Feature: Shortcuts and the panel
  The user can process text from other apps with the keyboard.

  Rule: Each of the four actions has its own shortcut
    Scenario: Configure separate entries
      When the user sets shortcuts for Translate, Polish, Translate and Replace, and Polish and Replace
      Then each shortcut invokes its action
      And Polish and Replace writes back to the original selection right after the result is generated

  Rule: Buttons have fixed shortcuts and hover tooltips
    Scenario: Hover to see the action and its key
      When the user rests the pointer on an icon button in the panel or the main window
      Then the action name and its key are shown
      And they are shown in the same way in the panel that does not activate the app
      And controls in the Settings window show no tooltip

    Scenario: Copy respects the selection
      Given the panel or the main window has a result
      When the user presses ⌘C
      Then the selected text is copied when text is selected
      And the current result is copied when no text is selected

    Scenario: The Shortcuts page lists the fixed keys
      When the user opens the shortcut settings
      Then the fixed keys are listed in the groups Panel, Translate & Polish, and Notebook and History
      And the fixed keys cannot be changed

    Scenario: Shortcut registration fails
      Given the chosen shortcut cannot be registered
      When the user saves the shortcut
      Then the app clearly says that registration failed
      And it is not shown as an available shortcut

  Rule: The panel supports keyboard operation and recovery from problems
    Scenario: Close the panel with the keyboard
      Given the text processing panel is open
      And no lookup card is open
      When the user presses Esc
      Then the panel closes

    Scenario: Losing focus does not close the panel
      Given the text processing panel is open
      When the panel loses keyboard focus
      Then the panel stays open

    Scenario: Clicking outside closes the panel
      Given the text processing panel is open
      When the user clicks outside the panel
      Then the panel closes

    Scenario: Clicking inside does not close the panel
      Given the text processing panel is open
      When the user clicks inside the panel
      Then the panel stays open

    Scenario: Not authorized to read the external selection
      Given the app lacks the permission needed to read external selections
      And the floating toolbar has not expanded yet
      When the user invokes the plain Translate shortcut
      Then a compact permission notice with an inline permission settings entry is shown
      And the full floating toolbar does not expand

  Rule: Immediate actions and content management are presented separately
    Scenario Outline: Every shortcut brings up the floating toolbar
      Given the user is reading text in another app
      And the selected text has been read and the required permissions and service configuration are in place
      When the user invokes the "<action>" shortcut
      Then a compact floating toolbar without a sidebar is shown
      And the full management window does not open
      And the result and study content can be expanded on demand
      Examples:
        | action |
        | Translate |
        | Polish |
        | Translate and Replace |
        | Polish and Replace |

    Scenario: Open settings from the toolbar
      Given the floating toolbar is open
      When the user opens settings
      Then settings are shown in the full management window
      And the floating toolbar is still brought up by global shortcuts

    Scenario: View accumulated content
      Given the user is in the floating toolbar
      When the user opens the notebook or history
      Then the content is shown in the full management window
      And the first version shows no review flow

  Rule: The first quick action stays compact while processing and shows the result when done
    Scenario Outline: Process selected text
      Given the user has selected text
      And the floating toolbar has not expanded yet
      When the user invokes the "<action>" shortcut
      Then a compact bar with a processing indicator, a text summary and a loading state is shown
      And Esc closes it and cancels the operation
      And no full result placeholder area is shown
      When processing finishes
      Then the result view expands smoothly
      Examples:
        | action |
        | Translate |
        | Polish |
        | Translate and Replace |

    Scenario: Reduce motion
      Given the user has turned on Reduce Motion
      When text processing finishes
      Then the result view is shown directly without the expand animation

  Rule: Shortcuts can be re-recorded
    Scenario: Record a new combination
      Given the user opens the shortcut settings
      When the user clicks the Translate shortcut and presses a new key combination
      And saves the settings
      Then the new combination opens the translate panel from then on
      And the old combination no longer triggers Translate
      And the new combination is kept after a restart

    Scenario: Cancel recording
      Given the user is recording a shortcut
      When the user presses Esc
      Then this recording is cancelled and the old combination is kept
      And the Settings window does not close

    Scenario: Conflict with another action
      Given Polish already uses a shortcut
      When the user records the same shortcut for Translate
      Then a conflict is reported and recording keeps waiting for input
      And both shortcuts in effect stay unchanged

    Scenario: No default shortcut on first use
      Given the user has not recorded a Translate shortcut
      When the user presses any combination
      Then Translate is not triggered
      And the Shortcuts page shows "Record"

  Rule: The full app handles translate and polish in one place
    Scenario: Switch the processing mode inside the app
      Given the user opens the text processing page of the full app
      When the user types or pastes text
      Then Translate or Polish can be chosen and run on the same page
      And there is no need to switch between two tabs or sidebar pages
      And the result can be copied

    Scenario: The sidebar offers no selection replacement action
      When the user looks at the left navigation of the full window
      Then there is only one text processing entry
      And there is no Translate and Replace navigation item
      And the separate Translate and Replace shortcut still brings up the panel

    Scenario: Switch the processing mode from the toolbar
      Given the user opens the Translate & Polish page of the full app
      Then the left of the toolbar is an icon-only Translate / Polish segmented control
      And the content is one glass card with margins on all sides
      And in the current pane the source and result sides are both visible, each as a group with a background
      And the target language is shown in the group header on the translation side
      And Copy Result and submit float at the bottom right of the content, replaced by Cancel while processing
      When the user switches to the other tab
      Then that operation's result is shown for the same source text without a repeat request

    Scenario: Polish does not choose a target language
      Given the user is on the text processing page of the full app
      When the user switches to Polish
      Then the Polish pane does not show the target language picker
      When the user switches back to the Translate pane
      Then the previously chosen target language is shown again
