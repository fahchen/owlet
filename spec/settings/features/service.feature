# English: service.feature · 简体中文: service.zh-CN.feature
Feature: Configure the model service yourself
  The user uses their own compatible service and API Key; settings live in a separate settings window.

  Rule: Settings are a separate window grouped into tabs
    Scenario: Open from the App menu
      When the user chooses "Settings…" in the App menu or presses ⌘,
      Then a separate settings window opens
      And the main window sidebar offers no settings entry

    Scenario: Tab grouping
      Given the user opens settings
      Then there are four tabs, General, Languages, Model, and Shortcuts (plus Debug when the debug switch is on), and Prompt belongs to the Model tab
      And settings within each tab are shown in groups

    Scenario: Return to the last tab
      Given the user last stayed on the Languages tab
      When the user opens settings again
      Then the Languages tab is shown directly

    Scenario: Changes take effect immediately
      Given the user opens settings
      Then there is no page-wide save button
      When the user changes any setting
      Then it takes effect immediately and is persisted

  Rule: The language subset limits the available languages
    Scenario: Default subset
      Given the user has not changed the language subset
      When the user opens the Languages tab
      Then it lists Simplified Chinese, English, and Japanese
      And the target language and the mapping table only offer these three languages

    Scenario: Add a language
      When the user adds a language on the Languages tab
      Then the language appears among the candidates for the target language and the mapping table

    Scenario: Removing a language cleans up
      Given a language is used in the mapping table and is the current fallback target
      When the user removes that language
      Then mapping rows that reference it are deleted with it
      And the fallback target moves to the first language in the subset

  Rule: The user decides where requests are sent
    Scenario: Save the service configuration
      When the user sets the compatible endpoint address, API Key, and model name
      And the user runs a translation
      Then that service and model process the text
      And the app explains that processed text is sent to the configured service

    Scenario: Incomplete configuration
      Given required model service configuration is missing
      When the user starts a translation
      Then the user is prompted to complete the configuration
      And the request is not sent to any other default service

    Scenario: Each provider remembers its own model name
      Given the user has filled in a model name for the compatible service
      When the user switches the provider to DeepSeek
      Then the model name changes to DeepSeek's preset model name
      And switching back to the compatible service restores the name the user entered
      And switching to a provider with nothing recorded yet uses that provider's default: an HTTP service uses its preset model, a local agent is left empty to use its own default model
      And switching and restoring are persisted immediately like other settings

    Scenario: Choose a provider preset
      Given the user opens the Model tab
      When the user chooses Moonshot / Kimi from the service list
      Then the Base URL is filled with that service's public address
      And the model name is filled with that service's default model
      And the user can still change the Base URL and model name
      And the choice is persisted immediately

    Scenario: The custom service remains available
      When the user chooses OpenAI Compatible
      Then the Base URL, model name, and API Key are all filled in by the user
      And choosing this entry does not change the address and model name the user already entered

    Scenario: The response format capability follows the selected service
      Given the user chooses a provider that only accepts json_object
      When the app builds a request
      Then the request's response format is json_object
      And the response shape is written in the System Prompt
      When the user chooses a provider that supports JSON Schema
      Then the request carries the JSON Schema

  Rule: Private credentials and local content are protected
    Scenario: Credentials are not exported with content
      Given the user has configured an API Key and saved expressions
      When the user exports the vocabulary
      Then the export does not contain the API Key

    Scenario: Content stays local
      Given the user has generated history and saved items
      When the user restarts the app
      Then this content can be read on this machine
      And no app account login or sync is required

  Rule: The user can customize the System Prompt
    Scenario: View the default and submit custom content
      Given the user has not changed the translate System Prompt
      When the user opens settings
      Then the full default translate Prompt is shown
      When the user edits the translate Prompt and leaves the editor
      Then later Translate and Translate and Replace use that configuration
      And the polish Prompt is unaffected

    Scenario: Restore the default
      Given the user has a custom polish Prompt
      When the user restores the default polish Prompt and leaves the editor
      Then later Polish uses the default content shown

    Scenario: Availability of the restore default entry
      Given the user has not changed the translate System Prompt
      Then the Restore Default button on the translate Prompt editor row is disabled
      When the user edits the translate Prompt
      Then the button is enabled
      And the Restore Default button on the polish Prompt editor row is unaffected

    Scenario: Reject a blank Prompt
      When the user tries to submit a System Prompt containing only whitespace
      Then the user is told it cannot take effect
      And the active configuration is unchanged

  Rule: The user can adjust reasoning effort
    Scenario: Keep the provider default
      Given the user has not set reasoning effort
      When the app builds a request
      Then the request contains no reasoning effort parameter
      And reasoning behavior is decided by the provider and model

    Scenario: Turn off or change reasoning effort
      Given the user sets reasoning effort to Off or a specific level
      When the app builds a request
      Then the request contains the corresponding reasoning effort parameter
      And the JSON response contract and local validation are unchanged

    Scenario: Levels map per model
      Given the user chooses a reasoning effort level
      When the current model supports that level
      Then the request sends the value that model accepts
      And when the model does not support that level, the nearest lower level is sent

    Scenario: The model does not use reasoning effort
      Given the current model does not accept a reasoning parameter
      When the user chooses any level
      Then the request contains no reasoning effort parameter

  Rule: A custom Prompt does not lift the JSON response contract
    Scenario: Non-JSON text is returned
      Given the user runs Translate and Replace
      When the model returns content that fails JSON contract validation
      Then the user is told the response format does not meet requirements
      And the source text is not replaced and nothing is saved as successful history

    Scenario: JSON pairs miss source text
      Given the source text contains two sentences
      When the JSON returned by the model only covers the first sentence
      Then the result is rejected and the source text is kept
