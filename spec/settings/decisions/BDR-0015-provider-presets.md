[English](BDR-0015-provider-presets.md) · [简体中文](BDR-0015-provider-presets.zh-CN.md)

# BDR-0015: Provider presets, and separating "protocol" from "vendor"

Status: Implemented (T75, 2026-10-15). Origin: user request to "add provider presets, so after choosing one only an API Key is missing".

## Background and problem

`Provider` originally did two jobs: **how to talk** (the `.openAICompatible` protocol) and **who to talk to** (`.deepSeek` carried a preset of `("https://api.deepseek.com", "deepseek-chat")`). As a result, every new OpenAI-compatible vendor needed a new enum case, and users who wanted Moonshot / Kimi, Zhipu GLM, Qwen / DashScope, xAI, OpenRouter, Ollama, or LM Studio had to look up the Base URL and model name themselves. The response format capability also hung off `Provider.supportsJSONSchema`, disguising "vendor behavior" as a "protocol property".

## Decision

### 1. `Provider` only represents the protocol and the two local agents

`Provider` is reduced to three cases: `openAICompatible`, `claudeCode`, `codexCLI`. The first is the delivery path "OpenAI-style HTTP service"; the other two are the local CLIs to run. `.deepSeek` is removed, because it describes a vendor rather than a protocol, which is exactly the confusion being fixed.

### 2. The vendor list is data: `ServicePreset`

Add a `ServicePreset` value type (`Owlet/Settings/ServicePreset.swift`) with fields for display name, Base URL, default model, response format capability, whether to read `GET /models`, and Keychain account. `ServicePreset.all` is the single source of truth: adding a vendor is one row of data and touches no enum, backend, or request construction.

The custom entry is one of the presets (`id == openAICompatible`, `baseURL == nil`) and the foundation of the whole list: every vendor ultimately uses the same `openAICompatible` delivery path, and a preset is only a convenience layer that fills in the address and model name for the user.

### 3. The response format capability follows the preset

`ServiceConfig` gains an optional `supportsJSONSchema`: a preset provides the vendor's answer, and `nil` falls back to the protocol's own default (`Provider.supportsJSONSchema`). `ModelClient.format` reads it to choose `.jsonSchema` or `.jsonObject`. As a result:

- Existing behavior of custom `openAICompatible` and the two local agents is unchanged (the protocol default is still "schema allowed");
- DeepSeek still sends only `{"type": "json_object"}`, and the shape stays in the System Prompt;
- Only vendors whose **documentation explicitly states** support for `response_format` with `json_schema` (including `name` / `strict` / `schema`) are marked true.

**Capabilities were checked against documentation only, without sending a request on a real account for each**: there are no keys for these vendors on this machine. The ones verifiable in documentation and marked schema-capable are **Moonshot / Kimi** (its response_format documentation gives the same structure as OpenAI) and **xAI** (its structured outputs documentation is isomorphic). The rest either document only `json_object` (Zhipu GLM), vary by model or endpoint (OpenRouter; DashScope's `json_schema` only covers some model families), or have no verifiable documentation (Ollama, LM Studio); all of these use the safer `json_object`. Better to carry the shape in the prompt than to get a 400.

### 4. Model memory is slotted by "service", not by protocol

Following T67, "switching back to a previous provider restores its model name", the slot becomes `service.model.<service id>`:

- For HTTP vendors the id is the preset id, so `service.model.deepSeek` and `service.model.openAICompatible` keep the same names and meanings as before, and old installs' memory is **compatible in place**;
- For local agents the id is `Provider.rawValue`, so `service.model.claudeCode` and the like are also unchanged;
- The unit must be the vendor (not the protocol): Moonshot, GLM, and DeepSeek are all `openAICompatible`, and a shared slot would let `glm-5.3` follow the user to Moonshot.

### 5. Persist one "service choice"; the old key is only migration input

The new key `service.choice` stores the current choice: the preset id for HTTP vendors, `Provider.rawValue` for local agents. The old key `service.provider` is no longer written and is only a fallback on read. Its stored values (`deepSeek`, `claudeCode`, `codexCLI`, `openAICompatible`) all happen to be valid service ids, so old installs need no one-off migration script: the first read yields the same service, Keychain account, and capabilities as before the upgrade. Keychain account: the custom entry is still `default`, other vendors equal their preset id, so an existing DeepSeek key keeps working.

## Alternatives rejected

- **One `Provider` case per vendor**: the most direct in types, but every new vendor changes the enum, capability table, model list branch, and tests, and it permanently couples "protocol" and "vendor", which is exactly the coupling being split here.
- **Making the local agents `ServicePreset`s too**: the list and persistence would be more uniform, but agents have no Base URL, default model, or Keychain account; forcing them in would make half the preset's fields meaningless for them. Keeping `Provider` as "protocol + two agents" is more honest.
- **Turning on `GET /models` for new vendors at the same time**: apart from DeepSeek, no vendor's `/models` behavior or auth differences were checked on this machine. Only the existing DeepSeek model dropdown is kept, to avoid turning "fill in the default model" into "an empty dropdown that cannot load".
- **Marking unverified vendors schema-capable**: a 400 is far worse than carrying the shape in the prompt; local validation is equally strict for both, so the safe value costs nothing in correctness.

## Consequences and known risks

- The default model is only "the name filled in the first time it is selected". The user can change it, and it does not break when the vendor changes things; it is only an initial value.
- Model names in vendor documentation will change; this table needs updating with the documentation (like `Provider`'s CLI flags, it is "external behavior").
- **Unverified**: any end-to-end call to a real vendor (no keys). So the true values of `supportsJSONSchema` only reach the "documentation is isomorphic" level; real response quality, whether model names are still available, and regional differences in Base URLs (such as DashScope's new workspace domain) are left to manual acceptance.
