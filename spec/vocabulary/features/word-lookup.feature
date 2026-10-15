# English: word-lookup.feature · 简体中文: word-lookup.zh-CN.feature
Feature: Looking up words while reading
  While reading, the user looks up a word, phrase or whole sentence on the spot, understands it and hears it pronounced, without leaving the text.
  Step one offers a lookup card and an explicit "Add to Notebook"; there is no query input field or query history, and a lookup by itself is never saved automatically.

  Rule: ⌘-click in read-only text looks up a word; selected text needs an explicit lookup (changed from a plain click to ⌘-click on 2026-10-11)
    Scenario Outline: ⌘-click a word in read-only text
      Given the user is reading the read-only text of "<area>"
      When the user holds ⌘ and clicks the word "running"
      Then a lookup card opens next to the word immediately
      And the lookup range is that word
      And the text content and paragraph layout do not change
      Examples:
        | area |
        | floating panel |
        | text processing page result |
        | notebook details |
        | history details |
        | study expressions |

    Scenario: A click without ⌘ is a normal text click
      Given the user is reading read-only text
      When the user clicks the word "running" without holding ⌘
      Then no lookup card opens and no lookup request is sent
      And the caret is placed or the selection is cleared as the system does

    Scenario Outline: Look up explicitly after selecting
      Given the user has selected a "<content>" in the text or in study expressions
      Then a selection toolbar containing "Look Up" is shown
      And no lookup card opens and no lookup request is sent
      When the user looks up through "<entry point>"
      Then the same kind of lookup card opens
      And the lookup range is exactly the selected text
      Examples:
        | content | entry point |
        | word | the selection toolbar's "Look Up" |
        | phrase | the selection toolbar's "Look Up" |
        | whole sentence | the context menu's "Look Up Selection" |

    Scenario: Double-click word selection and drag selection do not trigger a lookup
      Given the user is reading read-only text
      When the user double-clicks a word or drags to select some text
      Then the corresponding text selection is kept
      And no lookup card opens and no lookup request is sent
      And the user can still copy the selected text with the copy action

    Scenario: No lookup for a stale selection or an invalid hit
      Given the user has selected "running"
      When the user clears or changes the selection
      Then the selection toolbar can no longer look up the old "running" selection
      And with no selection, or only whitespace or punctuation, no lookup can be started
      And ⌘-clicking empty space outside a word, trailing whitespace on a line or punctuation does not look up a neighbouring word

  Rule: Study rows keep click-to-save, and editable areas stay editable
    Scenario: Clicking a study row and looking up a selection are independent
      Given the study expression "follow up" is not saved yet
      When the user clicks the study row
      Then the expression is saved under the existing saving rules
      And no lookup card opens
      When the user clicks the study row again
      Then it is unsaved under the existing rules
      When the user drags to select "follow up" in it and clicks the toolbar's "Look Up"
      Then a lookup card for the selected text opens
      When the user holds ⌘ and clicks "follow" in it
      Then a lookup card for that word opens
      And dragging, ⌘-clicking and looking up never change the saved state

    Scenario: Lookup does not make input fields read-only
      Given the user is editing the source text on the text processing page or a notebook editable field
      When the user clicks some text in it and types
      Then placing the caret and editing text still work
      And a click does not open a lookup card

  Rule: ⌘-click uses system word segmentation; a manual selection takes precedence
    Scenario: Correct Chinese or Japanese segmentation by selecting by hand
      Given the user ⌘-clicked a word the system recognised in Chinese or Japanese read-only text
      And that range is not the whole expression the user wants
      When the user selects the expression they want by hand and runs "Look Up"
      Then the lookup card looks up the whole manual selection
      And does not widen or narrow it by system segmentation

    Scenario: Holding ⌘ while hovering previews a lookup without changing the selection
      Given read-only text contains a word that can be looked up
      When the user moves the pointer over the word without holding ⌘
      Then there is no hover feedback and the pointer is a text cursor
      When the user holds ⌘
      Then the unselected word under the pointer shows system hover feedback distinguishable from the selected state
      And the pointer becomes a hand
      And the text size, spacing and paragraph layout do not change
      And no lookup is sent
      When the user releases ⌘ or moves the pointer away
      Then the hover feedback disappears and the pointer returns to a text cursor
      And an existing selection does not also show hover feedback

  Rule: With a source sentence, explain the meaning in context; without one, clearly give the general meaning
    Scenario: The lookup covers a local context containing the whole selection
      Given the user has selected "bank" in "We sat on the bank of the river."
      When the user looks it up and there is no reusable result
      Then the lookup uses a local context containing the selection
      And the lookup card explains the meaning in that sentence
      And may add the part of speech or usage when needed, without listing other senses
      When the user selects text spanning sentences instead and looks it up
      Then the query and the context cover the whole selection
      And the selection is not truncated while still claiming to explain all of it
      And the full text is not used as the context by default

    Scenario: An overlong selection is refused, not truncated
      Given the selected text is longer than 300 characters
      Then the selection toolbar shows a disabled "Look Up" with the reason "The selection is longer than 300 characters; shorten it to look it up"
      And no lookup is sent with a truncated selection
      When the selected text is within the limit but its sentence is longer than 1200 characters
      Then the local context is a 1200-character slice centred on the selection and fully containing it

    Scenario: The expression has no source sentence
      Given an expression that can be looked up has no source sentence context
      When the user looks up the expression
      Then the lookup card gives the general meaning and marks it "No source sentence"
      And no source sentence is invented

  Rule: The meaning language follows the source rules; no picker is added
    Scenario Outline: The source decides the meaning language
      Given the target mappings are "English → Simplified Chinese" and "Simplified Chinese → English"
      And the fallback target is Simplified Chinese
      And the user is viewing "<source>"
      When the user looks up "<expression>" in it
      Then the meaning is in "<meaning language>"
      And the lookup card offers no separate meaning language picker
      Examples:
        | source | expression | meaning language |
        | the English source text of an English to Chinese result | bank | Simplified Chinese |
        | the English translation of a Chinese to English result | bank | English |
        | an English polish result | bank | Simplified Chinese |
        | a Japanese polish result, with no target mapping for Japanese | 銀行 | Simplified Chinese |
        | a study expression in Chinese to English history details | follow up | English |
        | Chinese polish history details | 收敛 | English |
        | a notebook entry whose meaning language was recorded as English, after the target mapping changed | 收敛 | English |

  Rule: The title is the queried form; the lemma and reading are shown only when they apply
    Scenario: The queried form differs from the lemma
      Given the user looks up "running"
      When the model gives the lemma "run" and a reading in the current notation
      Then the lookup card uses "running" as its title
      And shows "run" and the reading as secondary information
      And does not replace the queried form with the lemma

    Scenario: No padded lemma, reading or sentence part of speech
      Given the queried expression already has a valid meaning
      When the lemma equals the form, the lemma is unknown or the reading cannot be determined
      Then an identical lemma is not shown twice and missing fields are not invented
      And a missing reading does not make a valid meaning fail
      And when there is a reading, it uses the reading notation set for that text language
      When the user looks up a whole sentence
      Then no reading or part of speech is shown
      And the meaning can still be viewed and the whole sentence can be spoken

  Rule: Identical lookups are reused; an older cross-sentence explanation must show its source and needs the user to look up again
    Scenario: The same conditions across reading areas reuse the result or wait for the same lookup
      Given in this launch the same text, local context and position of the selection in that context have been looked up
      And the text language, meaning language, reading notation and model settings that affect the explanation have not changed
      When the user starts the same lookup in another reading area
      Then if it succeeded, the existing result is shown directly
      And if it has not finished, the in-progress state of the same lookup is shown
      And no duplicate lookup request is sent

    Scenario: The same word in a new sentence first shows the older explanation with its source
      Given in this launch "bank" already has a successful explanation in a riverbank context
      And the old and current lookups have the same text language, form and explanation settings
      When the user looks up "bank" in a banking context
      Then the old explanation is shown, clearly marked "This meaning comes from another sentence"
      And the riverbank source context is shown
      And "Look Up in This Sentence" is offered
      And no request is sent automatically and the old explanation is not presented as the meaning in the banking context
      When the user runs "Look Up in This Sentence" and the lookup succeeds
      Then the explanation for the current banking context is shown
      And the explanation for the riverbank context is not overwritten

    Scenario Outline: Without an exact result, an incompatible cross-sentence explanation is not shown
      Given in this launch there is a successful older lookup result with a real source context
      And the current context has no result for the same conditions
      When the current lookup differs in "<difference>"
      Then the older result is not reused
      And this explicit lookup sends a new lookup request
      Examples:
        | difference |
        | the text language, or it is not yet known |
        | the queried form, even with the same lemma |
        | the meaning language |
        | the reading notation |
        | model settings that affect the explanation |

    Scenario: A general explanation without context does not pose as another sentence's explanation
      Given in this launch there is a general explanation with the same form, language and settings but no source sentence context
      When the user looks up that word in text that has a source sentence context
      Then the general explanation is not shown as "from another sentence"
      And this explicit lookup sends a new request for the current context
      When the user looks it up again under the same no-context conditions
      Then the original general explanation can be reused exactly
      And it is still marked "No source sentence"

    Scenario: A failed re-lookup in the current context keeps the older explanation
      Given the lookup card is showing an explanation from another sentence, with its source marked
      When the user looks up again in the current context and it fails
      Then the old explanation and its source context can still be read
      And the old source marker stays, along with this failure and a retry action
      And the old explanation is not saved as a successful result for the current context

    Scenario: Lookup records are reused only within this launch, with a limit
      Given the user has looked up many expressions in this launch
      Then the reusable records have a capacity limit
      When the user quits, relaunches the app and looks up the same expression again
      Then results or failures from the previous launch are not reused
      And the app has no persistent query history

  Rule: A failed lookup can be retried, and an invalid result is never treated as success
    Scenario Outline: Service or response failure
      Given the user explicitly looks up an expression
      When "<failure>"
      Then the lookup card explains the failure and offers a way to recover or retry
      And this response is not shown as a successful meaning
      And the text and existing entries stay as they were
      Examples:
        | failure |
        | no model service is configured |
        | the lookup request fails |
        | the response structure does not match the lookup contract |
        | the response does not correspond to this lookup's text |
        | the returned language tags do not match this lookup's contract |

    Scenario: Reopening a failed lookup does not resend automatically
      Given the lookup under the current conditions has failed
      When the user closes and reopens a lookup card with the same conditions
      Then the failure state is shown and no request is resent automatically
      When the user explicitly runs "Retry"
      Then the lookup is sent again
      And the failure does not stop the user from looking up in other contexts

  Rule: The lookup card is never overwritten by an older response, and does not reopen itself after closing
    Scenario: Switching lookups quickly
      Given the user looks up A and then immediately looks up B
      When the result for A arrives after the result for B
      Then only the lookup card for B is kept
      And the result for A neither overwrites B nor opens another card

    Scenario: An older result does not pop back after closing or leaving
      Given the lookup card is looking something up
      When the user closes the card or leaves the page
      And the lookup completes afterwards
      Then the lookup card does not pop up again

    Scenario: Lookups in the floating panel keep reading focus and close in layers
      Given the user has selected text in the floating panel and opened a lookup card
      Then the selected text can still be copied
      And using the selection toolbar or the lookup card does not close the floating panel
      When the user presses Esc
      Then the lookup card closes first and focus returns to the text
      And the floating panel stays open
      When the user presses Esc again
      Then the floating panel closes under its existing rules

  Rule: Pronunciation is played by the user on demand and never blocks the meaning
    Scenario: Speak the queried form on demand and stop earlier audio
      Given the lookup card's title is "running" and its lemma is "run"
      And a system voice is available for that text language
      When the user opens the lookup card
      Then nothing is spoken automatically
      When the user runs "Speak"
      Then "running" is spoken with an available system voice for that text language
      And the displayed reading string is not read out directly
      When the user plays again, switches cards or closes the card
      Then the earlier audio stops
      And new audio starts only when the user plays again

    Scenario: No usable voice, or the text language is unknown
      Given the expression's text language has no usable system voice or is not yet known
      When the user views the lookup card
      Then the pronunciation button stays but is disabled, with the reason "No system voice available"
      And the pronunciation language is not guessed from the page language
      And the meaning can still be viewed, without first downloading a voice

  Rule: Keyboard and accessibility users can reach the same lookup action
    Scenario: Look up without relying on hover
      Given the user is reading text with the keyboard or VoiceOver
      When the user selects text and finds the lookup action
      Then they can trigger the same lookup as the toolbar or the context menu
      And they are told when the lookup is in progress or has failed
      And they can close the card and keep reading

  Rule: A lookup is not saving or writing back (since 2026-10-11 the card can explicitly add to the notebook)
    Scenario: Looking up by itself changes no saved content
      Given the user is reading a notebook entry that already has a meaning, or a text processing result
      When the user looks up, looks up again or plays the pronunciation
      Then no notebook entry is added and nothing is saved automatically
      And saved meanings, readings and user edits are not overwritten
      And nothing is written back to the text or the source app

    Scenario: Explicitly add to the notebook from the card
      Given the lookup card shows this lookup's meaning
      When the user runs "Add to Notebook"
      Then an entry with the same language and expression is created or reused, using the queried form, this context and that meaning
      And the meaning, meaning language and known lemma come from this lookup's result, with no extra model request
      And the card stays open and the action shows "Saved"
      And nothing is written back to the text or the source app

    Scenario: Remove from the notebook in the card
      Given the word is already in the notebook and the card shows "Saved"
      When the user runs the action again
      Then the entry is removed from the notebook immediately and the action returns to not saved
      And no confirmation or extra submit is needed

    Scenario: Save the same word again from another sentence
      Given the word has already been saved from one sentence
      When the user looks up the same word in another sentence and adds it to the notebook again
      Then the existing entry is reused and this context is appended
      And the existing meaning and source sentences are not overwritten

    Scenario: A failed add does not interrupt reading
      Given the user runs "Add to Notebook"
      When saving fails
      Then the card shows the failure and keeps the meaning readable
      And the notebook stays as it was

    Scenario: A lookup without context can also be added
      Given the lookup has no source sentence context
      When the user runs "Add to Notebook"
      Then the entry stores the queried form and this meaning, without a fake source sentence
      And the card still marks it "No source sentence"
