[English](roadmap.md) · [简体中文](roadmap.zh-CN.md)

# Owlet · Roadmap

What is still open. Behaviour is defined in `spec/`; shipped changes are listed in [CHANGELOG.md](../CHANGELOG.md). New work gets an entry here with its acceptance conditions and how it will be verified; remove the entry once it ships and is verified.

## Waiting for acceptance

Implemented, but some of the evidence can only come from a person or a real environment.

| Item | What is left | Where |
| --- | --- | --- |
| Floating panel built from the Figma board | Visual review against the board: corner radii, error text colour, active glass, interaction states. | [Panel debugging and testing](panel-debugging-and-testing.md) |
| Word lookup, step one | All five reading areas work; still to accept: spoken pronunciation with a real system voice, real VoiceOver, and an installed build. | [word-lookup.feature](../spec/vocabulary/features/word-lookup.feature), [BDR-0008](../spec/vocabulary/decisions/BDR-0008-reading-word-lookup.md) |
| Corrective retry for study suggestions | Re-check against real models that the one corrective round repairs a broken reply. | [LLM contract](../spec/llm/contract.md) |
| Selected text capture | The Accessibility path, the ⌘C fallback and paste write-back are implemented; compatibility across real apps still needs a hand check. | [selected-text-capture.md](selected-text-capture.md) |
| Streaming model output | Partial text is shown while the reply arrives and nothing partial is trusted; still to accept: a real OpenAI-compatible service, a real local agent, and an installed build. | [streaming-output.md](streaming-output.md), [BDR-0017](../spec/processing/decisions/BDR-0017-streaming-display.md) |

## Proposals not yet in the product definition

- **Screen region OCR input.** Draw a rectangle on screen and read its text with Vision; copy only, nothing to write back. See [screen-region-input.md](screen-region-input.md).
- **Continuous speech input.** See [speech-input.md](speech-input.md). Not planned for now.

## Not in the first version

Review, spaced repetition and mastery tracking; automatic collection; sync and accounts; multiple polish variants and tone presets. See [product.md](../spec/product.md), *Not in the first version*.
