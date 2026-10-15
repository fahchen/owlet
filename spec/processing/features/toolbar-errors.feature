# English: toolbar-errors.feature · 简体中文: toolbar-errors.zh-CN.feature
Feature: Errors and recovery in the floating toolbar
  On an error, the user can find a way to recover, and an already open processing interface is kept.

  Rule: The panel shows a separate source bar and status bar
    Scenario: Process text for the first time
      Given a quick action has read the source text
      When the text is being processed
      Then the source text is shown in a single-line summary bar with a close entry
      And a separate status bar below shows the current operation and a cancel entry
      And a transparent gap is kept between the two bars

    Scenario: The first request fails
      Given a quick action has read the source text
      When the request fails or the model service is not configured
      Then the source summary is kept with retry and close entries
      And a separate status bar below shows the error and the matching recovery entry

    Scenario: View a successful result
      Given the quick action succeeded
      Then the source text and the result are expanded
      And the close and copy entries are at the bottom right
      When the user expands the study content
      Then the result and the study items sit side by side and scroll separately

    Scenario: Close a panel that is still processing
      Given the panel is processing text
      When the user clicks close or presses Esc
      Then the panel closes and cancels the unfinished operation
      And a late result must not write back or reopen the panel

  Rule: Before the toolbar opens, a blocked action shows only a compact notice
    Scenario Outline: A quick action cannot continue
      Given the floating toolbar has not expanded yet
      When Translate, Polish or Translate and Replace hits "<problem>"
      Then an understandable compact notice is shown
      And "<entry>" is offered next to the notice
      And the full floating toolbar does not expand
      And the original selection is not modified
      Examples:
        | problem | entry |
        | the selected text cannot be read | Enter Text |
        | the permission to read the selection is missing | Permission Settings |
        | the model service is not configured | Configure Service |
        | the model service connection or authentication failed | Service Settings |
        | the returned format does not meet the requirements | Prompt Settings |
        | writing back to the original app failed and a result exists | Copy Result |
        | the operation was cancelled | Try Again |

  Rule: An expanded toolbar does not collapse on errors
    Scenario Outline: Keep the existing working interface
      Given the user has already opened the translate or polish toolbar
      When a later operation hits "<problem>"
      Then the toolbar stays expanded
      And the error and an inline "<entry>" are shown in the content area
      And the source text and any results that are still usable are kept
      And the original selection is not modified
      Examples:
        | problem | entry |
        | the selected text cannot be read | Enter Text |
        | the permission to read the selection is missing | Permission Settings |
        | the model service is not configured | Configure Service |
        | the model service connection or authentication failed | Service Settings |
        | the returned format does not meet the requirements | Prompt Settings |
        | writing back to the original app failed | Copy Result |

    Scenario: Reprocessing fails after expanding
      Given the floating toolbar shows the source text and the result
      When the user reprocesses the text
      Then the toolbar stays expanded and shows the processing state
      When the service request fails
      Then the toolbar still stays expanded and reports the failure in the content area
      And the user can open the service settings or retry

    Scenario: Cancel processing after expanding
      Given the user is reprocessing text in the expanded toolbar
      When the user chooses to cancel processing rather than close the toolbar
      Then the toolbar stays expanded and shows a cancelled notice
      And the user can process again
      And this operation does not replace the original selection

  Rule: A recovery entry points to the matching problem
    Scenario Outline: Open the matching settings
      Given the user sees a "<problem>" notice
      When the user chooses the settings entry in the notice
      Then "<settings>" opens
      Examples:
        | problem | settings |
        | the permission to read the selection is missing | the system's selection reading permission settings |
        | the model service is not configured | the model service configuration |
        | the model service connection or authentication failed | the model service configuration |
        | the polish reply's format does not meet the requirements | the polish prompt settings |
        | the translation reply's format does not meet the requirements | the translation prompt settings |

  Rule: The result panel expands continuously
    Scenario: Expand the result when the request finishes
      Given the panel is processing the source text
      When a valid result returns
      Then the source bar expands downward into the result panel with a subtle spring animation
      And the top of the source bar stays in place (except where constrained by the screen edge)
      And the result is shown directly when the system's Reduce Motion is on
