# English: local-agent.feature · 简体中文: local-agent.zh-CN.feature
Feature: Use a local agent CLI as the model service
  A Claude Code or Codex CLI already logged in on this machine can be used directly as the model service: the app only asks it for one answer,
  and does not treat it as a coding agent that reads and writes code (BDR-0013).

  Rule: Local agents are selectable alongside HTTP services
    Scenario: Select a local agent
      Given the user is logged in to an agent CLI on this machine
      When the user selects it as the provider in settings
      Then the settings page no longer asks for a Base URL and API Key
      And translate, polish, lookup, and study all use it

    Scenario: The provider list always shows every local agent
      Given the user sees two groups in the provider list, remote services and local agents
      When an agent CLI is not installed on this machine
      Then that agent still appears in the list, labeled not detected
      And the user can choose that agent's executable by hand right there
      And the remote services group is unaffected

    Scenario: Lookup follows the user's own shell and does not depend on the app's launch environment
      Given the app was launched from Finder and inherited only the minimal system PATH
      When the app looks for an agent CLI
      Then it searches the way the user's login shell would, giving that shell a PATH that includes the standard install directories
      And when the login shell cannot find it, it searches once more with an interactive login shell, because .zshrc is read only by interactive shells
      And when both shells fail, it checks common locations directly, such as ~/.local/bin, ~/.claude/local, /opt/homebrew/bin, and /usr/local/bin
      And the result does not depend on the PATH the app itself was launched with
      And the direct check only enumerates known directories and never walks the whole home directory

    Scenario: Switching to a local agent scans actively
      Given an agent CLI is installed on this machine and the user has not set a path for it
      When the user selects it as the provider
      Then the app finds it automatically, fills in the executable, and shows the version
      And the user does not need to click "Detect" first

    Scenario: A non-executable path counts as missing configuration
      Given the user selected a local agent but has no executable path, or the path is no longer executable
      When the user starts a translation
      Then the user is prompted to complete the configuration
      And the request is not sent to any default service

    Scenario: The path comes from detection or a manual choice
      When the user clicks "Detect"
      Then the app looks for the agent the way the user's login shell would and shows the detected version
      And when detection fails it explains why in place and suggests choosing manually, without changing the saved path
      And a path the user picked by hand is not overwritten by scan results unless it is no longer executable

    Scenario: Switching providers does not keep the previous service's model name
      Given the user filled in a model name for an HTTP service
      When the user changes the provider to a local agent
      Then the model name is left empty and the agent's own default model is used

  Rule: Queryable capabilities are provided per provider
    Scenario: Choose a model from the agent's own list
      Given the user selected Codex CLI in settings
      When the app reads that agent's model list
      Then the model name is offered as a dropdown whose first item is the agent's own default model
      And models marked as hidden in the list do not appear

    Scenario: A provider that lists effort levels provides them per model
      Given the user selected a model on Codex CLI
      When the app reads the model catalog
      Then reasoning effort maps to the value range that model declares, and an unsupported level takes the nearest lower level within that model
      And when the model declares no reasoning support at all, the request sends no effort parameter
      And Claude Code gets the same per-model data from its own cached model catalog

    Scenario: Read the list from Claude Code's own cached model catalog
      Given the user selected Claude Code in settings
      When the app can read its cached model catalog
      Then the model name is offered as a dropdown whose first item is the agent's own default model
      And when a model declares a reasoning effort range, the supported levels are shown right under the effort row
      And a saved model name that is not in the list remains selectable

    Scenario: Claude Code stays free-form when the cache cannot be read
      Given the user selected Claude Code in settings
      When its cached model catalog is missing, empty, or has changed shape
      Then the model name is a free-form text field and no error is shown
      And leaving it empty means using its own default model
      And the saved model name is unchanged and requests can still be sent

    Scenario: Reading the list fails
      When reading the model list fails
      Then the reason is shown in place under the model name row with a retry option
      And the saved model name is unchanged

  Rule: Agents that can constrain the response shape use their flag
    Scenario: The agent gets the same schema used for local validation
      Given the selected agent accepts a response schema
      When the app builds a translation, study, or lookup request
      Then the request carries the contract's schema (a file for Codex, an argument for Claude Code)
      And local validation and correction retry are not relaxed at all

    Scenario: A provider that does not accept a schema carries the shape in the prompt
      Given the selected provider is DeepSeek or another service that only supports json_object
      Then the request only asks for JSON
      And the shape is still carried by the prompt and enforced by local validation

  Rule: Borrow only the model, not its tools or context
    Scenario: Both agents run with tools and context off
      Given the user selected either local agent in settings
      When the app sends a request
      Then Claude Code runs with all tools and all customizations disabled
      And Codex does not read the user config, so its MCP servers are not connected, user hooks do not run, and the shell tool is off
      And both use a throwaway empty directory as working directory

    Scenario: The user's sessions and project files are not read
      When the app sends a request
      Then the agent does not load the user's project configuration or session history
      And the temporary directory is deleted after the request ends

    Scenario: Requests still work after the CLI version changes
      Given the Codex CLI installed on this machine changed to another version
      When the settings page scans this agent
      Then requests only send the feature flags that version itself declares, plus config keys a local probe confirmed it accepts
      And before any scan only the two long-lived flags are sent, and no unverified config key
      And a flag missing in that version only means fewer things are turned off this time, never a failed request

  Rule: Responses still follow the same contract
    Scenario: Delivering the prompt and the source text
      Given a translation request
      When the app calls a local agent
      Then the behavior prompt and the fixed contract are delivered through that agent's channel
      And the user's source text never appears in command-line arguments

    Scenario: Replies are validated on the same path
      Given a local agent returned content
      When the app parses the reply
      Then structure, source concatenation, and target language validation are exactly the same as for HTTP services
      And on a contract failure it likewise corrects only once

    Scenario: Structured output on the json_object route
      Given the selected agent does not accept this app's response schema
      When the app builds the request
      Then the shape is written in the prompt and JSON is required
      And local validation is not relaxed because of it

  Rule: Failures are diagnosable
    Scenario: The agent exits non-zero
      When the agent exits with a non-zero status
      Then the message says the local agent failed and includes its error output
      And nothing is written back or saved as successful history

    Scenario: Timeout
      Given a request exceeded the configured timeout
      Then the app terminates the process and reports a connection failure

    Scenario: User cancels
      Given a local agent request is in progress
      When the user cancels
      Then the process is terminated
      And late output does not change the interface and is not written back

    Scenario: Debug page
      Given the user turned on the debug switch
      When a local agent request finishes
      Then the debug page records the command line and prompt actually executed, and the model's raw reply
      And the record contains no keys

  Rule: Resources are bounded
    Scenario: The number of concurrent processes is capped
      Given several requests start at once
      Then no more agent processes run at once than the configured limit, and the rest queue

    Scenario: No session files are left behind
      When the app calls a local agent
      Then each agent runs without persisting sessions
