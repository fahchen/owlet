# English: recommendations.feature · 简体中文: recommendations.zh-CN.feature
Feature: Optional study content
  The user decides whether to get study recommendations from translations and polishes.

  Rule: Study recommendations are off by default and controlled separately
    Scenario: First use
      Given the user has not changed the study settings
      When the user runs Translate and Polish
      Then neither operation automatically requests or shows study recommendations

    Scenario: Turn on only translation study
      Given the user turns on translation study and turns off polish study
      When the user completes a translation and a polish
      Then a separate study request starts automatically after the translation succeeds
      And Polish generates no study recommendations

    Scenario: Expand once
      Given the translation study toggle is off
      When the user expands the "Study" area below the result
      Then only then is a separate study content request made for this run
      And the long-term setting stays off
      And the next translation does not generate study content automatically

    Scenario: Expand already generated study expressions again
      Given this run's study expressions were generated successfully
      When the user collapses and expands them again
      Then the existing items are shown without a repeat request

  Rule: Study content excludes native languages
    Scenario: Exclude the native language while reading Japanese
      Given the user has set their native language to Simplified Chinese
      And the source text is Japanese and the target is Simplified Chinese
      When the translation succeeds and study content is requested
      Then the recommended items include no Simplified Chinese expressions
      And Japanese expressions can still be recommended

    Scenario: Polishing native-language text produces no study content
      Given the user has set their native language to Simplified Chinese
      And the source text is Simplified Chinese
      When polishing succeeds
      Then no study request is made and there is no study entry
      And the main result is still usable

    Scenario: Polishing non-native text recommends as usual
      Given the user has set their native language to Simplified Chinese
      And the source text is English
      When polishing succeeds and study content is requested
      Then English expressions are recommended

    Scenario: Behavior is unchanged when no native language is set
      Given the user has not set a native language
      When a translation or polish succeeds and study content is requested
      Then expressions on both the source and translation sides can be recommended

    Scenario: Local fallback when the model does not comply
      Given the user has set their native language to Simplified Chinese
      When the model returns a Simplified Chinese recommendation
      Then that item is dropped before it is shown

  Rule: Recommendations serve understanding and expression, without padding the count
    Scenario: Style suggestions in polishing
      Given the polish study toggle is on
      And the source text is grammatically correct but has style that could be improved
      When the user views the study content
      Then the difference before and after the change and the reason are explained
      And a pure style preference is not labeled a grammar error

    Scenario: Nothing worth recommending
      Given the study toggle is on
      When this result has no vocabulary, collocations or sentence patterns worth recommending
      Then there may be no recommended items
      And the main result is still usable

    Scenario: A recommended word appears in an inflected form in the sentence
      Given an expression in a Japanese source sentence is "跳ね上がっている"
      When the model recommends this expression and gives the dictionary form "跳ね上がる"
      Then the recommendation is usable and is not judged a format error because the surface form differs from the base form
      And the entry is saved as "跳ね上がっている", with "跳ね上がる" recorded as the base form
      And the base form is not recorded again when it equals the surface form

  Rule: Study content does not block the main action and is never saved automatically
    Scenario: Save items one by one in the panel
      Given the panel shows study recommendations
      When the user clicks a recommendation
      Then only that recommendation and its meaning are added to the notebook
      And it shows a selected state after saving succeeds
      And a retry entry is kept when saving fails

    Scenario: Direct replacement does not wait for study content
      Given the user has turned on translation study and runs Translate and Replace
      When the translation is generated and the original selection is valid
      And study content is still being generated
      Then the translation is written back directly
      And nothing is saved automatically

    Scenario: Study generation fails
      Given the user has a translation result
      When study content generation fails
      Then the translation result can still be copied
      And the user can retry study content generation

    Scenario: Study in the full window matches the panel
      Given the main result in the full window was generated successfully
      When the user clicks the Study button at the bottom right
      Then the study list is the same as in the panel, and clicking an entry toggles saving immediately
      And the study request reuses this translation's or polish's result and language information
      And there is no separate meaning language picker

  Rule: Study entries in the panel toggle saving immediately
    Scenario: Deselect an entry
      Given an entry in the panel is already in the notebook and shown as selected
      When the user clicks the entry again
      Then the entry is removed from the notebook immediately and shown as not selected
      And no confirmation or extra submit is needed
      And if removal fails, the selected state is kept and the failure is reported

    Scenario: Open the study view again
      Given an entry has been added to the notebook
      When the user opens a study view containing that entry again
      Then the entry is still shown as selected

    Scenario: The result switches to the study layout
      Given the panel is showing a translation result
      When the user expands Study
      Then the result smoothly reflows into two side-by-side columns with a spring transition
      And it switches directly when the system's Reduce Motion is on
