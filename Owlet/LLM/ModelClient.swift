import Foundation

enum ModelError: Error, Equatable {
    case network(String)
    case unauthorized
    /// A status outside 2xx. `detail` is the service's own body, kept for the Debug page: a 4xx or 5xx
    /// usually says what it objected to, and the app would otherwise show a bare number.
    case http(Int, detail: String?)
    case emptyResponse
    /// The returned JSON does not have the agreed shape: a missing or extra field, a wrong type, a
    /// blank segment, or text outside one code fence.
    case format
    /// The returned source text does not reassemble into what was submitted, so the pairing cannot
    /// be trusted even though the JSON itself was well formed.
    case sourceMismatch
    /// The model answered in another language than the one requested.
    case targetMismatch(requested: String, returned: String)
    case truncated
    case refused
    /// A local agent CLI could not be reached or did not answer: it is missing, exited with an error, or
    /// ran past its time limit. The detail is the agent's own error output.
    case localAgent(String)

    /// A failure reaches the user as its message, and that is all the panel keeps: the kind above
    /// decides what it means, this decides how it reads.
    var message: String {
        switch self {
        case .network(let detail):
            L10n.shared.string("Network error: %@", detail)
        case .unauthorized: L10n.shared.string("Authentication failed. Check the API key.")
        case .http(let code, _): L10n.shared.string("The service returned HTTP %lld.", code)
        case .emptyResponse: L10n.shared.string("The service returned empty content.")
        case .format:
            L10n.shared.string(
                "The reply does not match the agreed structure: a missing field, a wrong type, or empty content."
            )
        case .sourceMismatch:
            L10n.shared.string(
                "The returned source does not reassemble into what was submitted, so the pairing cannot be trusted."
            )
        case .targetMismatch(let requested, let returned):
            L10n.shared.string(
                "The reply is in %@, which does not match the requested %@.", returned, requested)
        case .truncated: L10n.shared.string("The result was cut off for being too long.")
        case .refused: L10n.shared.string("The service refused to process this text.")
        case .localAgent(let detail): L10n.shared.string("The local agent failed: %@", detail)
        }
    }

    /// The service's own words behind a failure, when it said anything. The Debug page shows this as
    /// the reply; nothing else reads it.
    var diagnosticBody: String? {
        if case .http(_, let detail) = self { return detail }
        return nil
    }

    /// What a failure means for the user. Classification is a property of the error, never of its
    /// wording: a translated message must not decide whether the way out is the prompt editor or the
    /// service settings, nor whether the problem is the connection.
    enum Kind: Equatable {
        /// A prompt edit can address it: the reply broke the contract.
        case contract
        /// Reaching the service failed: network, credentials or HTTP status.
        case connection
        /// The service answered, but the answer is unusable.
        case service
    }

    var kind: Kind {
        switch self {
        case .format, .sourceMismatch, .targetMismatch: .contract
        case .network, .unauthorized, .http, .localAgent: .connection
        case .emptyResponse, .truncated, .refused: .service
        }
    }
}

typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// A contract failure together with the model content that produced it, so a caller can show the model
/// what it must fix instead of asking again from scratch.
struct ContractError: Error {
    let error: Error
    let content: String
}

extension ModelClient {
    /// Whether a failure is worth one corrective round. A structure the app cannot read, a pairing that
    /// does not reassemble, or an explanation in the wrong language all describe something the model got
    /// wrong and can be told about. Truncation, refusal, an empty answer and transport failures cannot.
    static func isCorrectable(_ error: ModelError) -> Bool {
        switch error {
        case .format, .sourceMismatch, .targetMismatch: true
        case .network, .unauthorized, .http, .localAgent, .emptyResponse, .truncated, .refused: false
        }
    }

    func isCorrectable(_ error: ModelError) -> Bool { Self.isCorrectable(error) }
}

struct ModelClient: Sendable {
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    /// How a request reaches a local agent CLI. The HTTP providers never touch it, and the HTTP
    /// transport is never touched for a local-agent provider.
    var localAgent: LocalAgent = LocalAgent()
    /// Resolves the behavior prompt for an operation, so a saved custom prompt reaches assembly while
    /// a test can substitute a hostile one; the fixed contract is appended by the request builders
    /// either way.
    var promptForOperation: @Sendable (Operation) -> String = { SettingsStore.prompt(for: $0) }
    /// Where a finished exchange goes for the debug page; off by default so ordinary use never keeps
    /// the user's text.
    var capture: DebugCapture = .live
    /// The target mapping, for the language a recommendation is explained in (BDR-0005); injectable so
    /// a test can act as a different mapping.
    var targetMapping: @Sendable () -> TargetMapping = { SettingsStore.targetMapping() }
    /// The languages the reader already speaks, which recommendations skip (BDR-0012); empty means
    /// Not Specified.
    var nativeLanguages: @Sendable () -> [String] = { SettingsStore.nativeLanguages() }

    func translate(_ text: String, to targetLanguage: String, config: ServiceConfig)
        async throws -> String
    {
        try await process(text, operation: .translate, to: targetLanguage, config: config)
    }

    /// `targetLanguage` is ignored for polish, whose result must stay in the source language.
    func process(
        _ text: String, operation: Operation, to targetLanguage: String, config: ServiceConfig
    ) async throws -> String {
        try await processResult(text, operation: operation, to: targetLanguage, config: config).text
    }

    /// Returns the whole validated result so a caller can also read the source and target languages
    /// of a collected expression.
    func processResult(
        _ text: String, operation: Operation, to targetLanguage: String, config: ServiceConfig
    ) async throws -> TranslationResult {
        let target = operation == .translate ? targetLanguage : nil
        let request = try translationRequest(
            text: text, operation: operation, to: target, config: config)
        return try await perform(
            request, title: Self.debugTitle(operation: operation, target: target),
            symbol: operation.symbol, submitted: text, config: config,
            parse: { try TranslationResult.parse($0, submitted: text, targetLanguage: target) })
    }

    /// Names what was asked for, so a debug entry reads without opening it.
    static func debugTitle(operation: Operation, target: String?) -> String {
        let name = operation.name
        return target.map { "\(name) · \($0)" } ?? name
    }

    /// The format the provider can accept: a real schema where it takes one, `json_object` where the
    /// shape must travel in the system prompt instead. A vendor preset answers through the config; nil
    /// falls back to the wire protocol's own default (BDR-0015 §3).
    private func format(name: String, schema: [String: Any], config: ServiceConfig) -> ModelResponseFormat {
        let supported = config.supportsJSONSchema ?? config.provider.supportsJSONSchema
        guard supported,
            let data = try? JSONSerialization.data(withJSONObject: schema)
        else { return .jsonObject }
        return .jsonSchema(name: name, schema: data)
    }

    /// Fills in a meaning for one collected expression through the learning contract, in the language
    /// that entry is explained in (BDR-0005); the caller keeps the saved entry when this throws so the
    /// user can retry.
    func fillMeaning(
        expression: String, language: String, context: String, definitionLocale: String,
        config: ServiceConfig
    ) async throws -> String {
        let task = ModelPrompts.format(
            "fillMeaningTask", LanguageCatalog.name(for: definitionLocale))
        // The prompt text lives in ModelPrompts.json; `"\n"` keeps the blank line and the indent the
        // literal used to carry, so the model receives the same bytes.
        var system = task + "\n\n"
        system += "            " + ModelPrompts["fillMeaningShape"] + "\n"
        system +=
            "            "
            + ModelPrompts.format(
                "fillMeaningFields", LanguageCatalog.name(for: definitionLocale)) + "\n"
        system += "            " + ModelPrompts["fillMeaningExample"] + "\n"
        let payload = try JSONSerialization.data(withJSONObject: [
            "expression": expression, "language": language, "context": context,
        ])
        let request = ModelRequest(
            model: config.model, system: system,
            turns: [.user(String(decoding: payload, as: UTF8.self))],
            format: format(name: "meaning", schema: LearningResult.providerSchema, config: config),
            effort: config.effort, customEffort: config.customEffort,
            supportedEfforts: config.supportedEfforts)
        return try await perform(
            request, title: L10n.shared.string("Fill In Meaning"), symbol: "text.badge.plus",
            submitted: expression,
            config: config,
            parse: { try LearningResult.item($0, expression: expression).meaning })
    }

    /// Runs the optional learning request as its own call, so a failure here can only ever affect the
    /// learning area and never the main result the caller already has.
    ///
    /// A reply this app cannot accept buys one corrective round: the model is shown its own answer and
    /// which rule it broke, which is far more reliable than re-sending the same prompt and hoping. Only
    /// one round, so a model that cannot follow the contract still fails exactly where it did.
    func learning(
        text: String, operation: Operation, targetLanguage: String, result: String,
        config: ServiceConfig
    ) async throws -> [LearningResult.Item] {
        let request = try learningRequest(
            text: text, operation: operation, targetLanguage: targetLanguage, result: result,
            config: config)
        switch try await attempt(
            request, title: L10n.shared.string("Study Expressions"), submitted: text, config: config)
        {
        case .success(let items):
            return learnable(items)
        case .failure(let error):
            // Only a reply that arrived but broke the contract is worth correcting; truncation,
            // refusal, an empty answer and every transport failure stand as they are.
            guard let asModelError = error.error as? ModelError,
                isCorrectable(asModelError)
            else { throw error.error }
            // A reply with no JSON in it names no rule to follow, so it gets no second round.
            let reasons = LearningResult.diagnose(error.content)
            guard !reasons.isEmpty else { throw error.error }
            let correction = try learningRequest(
                text: text, operation: operation, targetLanguage: targetLanguage, result: result,
                config: config, correcting: error.content, reasons: reasons)
            switch try await attempt(
                correction, title: L10n.shared.string("Study Expressions (corrected)"), submitted: text,
                config: config)
            {
            case .success(let items): return learnable(items)
            case .failure(let retried): throw retried.error
            }
        }
    }

    /// Sends one request and parses it; the parse failure carries the content back, because the
    /// corrective round has to show the model the reply it must fix. Everything else throws.
    private func attempt(
        _ request: ModelRequest, title: String, submitted: String, config: ServiceConfig
    ) async throws -> Result<[LearningResult.Item], ContractError> {
        try await perform(
            request, title: title, symbol: "lamp.desk", submitted: submitted, config: config
        ) {
            (content: String) -> Result<[LearningResult.Item], ContractError> in
            do {
                return .success(try LearningResult.parse(content))
            } catch {
                return .failure(ContractError(error: error, content: content))
            }
        }
    }

    /// Builds the separate learning request: the same behavior prompt as the main request plus the
    /// learning task and the `$defs.learning` contract, with the original and result as data.
    ///
    /// With `correcting`, the same contract comes after the model's own rejected reply and the rules
    /// it broke, so the one thing that changes between the two requests is the model's own output.
    /// Drops recommendations in the reader's own language. The prompt says not to offer them, but a
    /// model does not always comply, and a phrase the reader already speaks is not worth learning
    /// (BDR-0012) — so the filter is here rather than trusted to the reply.
    private func learnable(_ items: [LearningResult.Item]) -> [LearningResult.Item] {
        let native = nativeLanguages()
        guard !native.isEmpty else { return items }
        return items.filter { item in !native.contains { LanguageTag.same($0, item.language) } }
    }

    func learningRequest(
        text: String, operation: Operation, targetLanguage: String, result: String,
        config: ServiceConfig, correcting reply: String? = nil, reasons: [String] = []
    ) throws -> ModelRequest {
        // BDR-0005: a translation is explained in its own target; a polish keeps the text's language, so
        // its explanations use that language's mapped target instead — not the language itself.
        let explainedIn =
            operation == .polish
            ? targetMapping().target(forSource: LanguageTag.key(targetLanguage))
            : targetLanguage
        let meaningLanguage = LanguageCatalog.name(for: explainedIn)
        let task = ModelPrompts.format(
            operation == .polish ? "learningTaskPolish" : "learningTaskTranslate", meaningLanguage)
        var system = promptForOperation(operation) + "\n\n"
        // The prompt text is data; the indent keeps the bytes the literal used to carry.
        system += "            " + task + ModelPrompts["learningPreamble"] + "\n"
        let native = nativeLanguages()
        if !native.isEmpty {
            // Named, not "your language": the model is told exactly which ones to leave out.
            let names = native.map(LanguageCatalog.name(for:)).joined(separator: "、")
            system +=
                "            " + ModelPrompts.format("learningSkipNative", names) + "\n"
        }
        system += "            " + ModelPrompts["learningShape"] + "\n"
        system += "            " + ModelPrompts.format("learningFields", meaningLanguage) + "\n"
        system += "            " + ModelPrompts["learningExample"] + "\n"
        let payload = try JSONSerialization.data(withJSONObject: [
            "original": text, "result": result,
        ])
        let user = String(decoding: payload, as: UTF8.self)
        let turns: [ModelTurn]
        if let reply {
            let problems =
                reasons.isEmpty
                ? "It does not satisfy the contract for items."
                : "These rules were broken: " + reasons.joined(separator: "; ") + "."
            turns = [
                .user("Original and result, as data:\n\(user)"),
                .assistant(reply),
                .user(
                    """
                    That reply was rejected. \(problems)
                    Reply again with only the one json object, keeping every meaning you already \
                    wrote and changing only what the rules require.
                    """),
            ]
        } else {
            turns = [.user(user)]
        }
        return ModelRequest(
            model: config.model, system: system, turns: turns,
            format: format(name: "learning", schema: LearningResult.providerSchema, config: config),
            effort: config.effort, customEffort: config.customEffort,
            supportedEfforts: config.supportedEfforts)
    }

    /// One explicit reading lookup through `$defs.lookup`. The context and offset come from the
    /// app's snapshot, so the model is only trusted for the explanation itself.
    ///
    /// As with learning, a reply this app cannot accept buys one corrective round naming the claims the
    /// model got wrong. A lookup is the app's most exacting contract — seven keys, nullable ones
    /// included, and a definition written in the language that was asked for — and a provider that
    /// breaks it usually has a fixable answer, not a bad one.
    func lookup(_ query: LookupQuery, config: ServiceConfig) async throws -> LookupResult {
        let request = try lookupRequest(query, config: config)
        let title = L10n.shared.string("Look Up · %@", query.definitionLanguage)
        switch try await attemptLookup(request, query: query, title: title, config: config) {
        case .success(let result):
            return result
        case .failure(let error):
            guard let asModelError = error.error as? ModelError, isCorrectable(asModelError) else {
                throw error.error
            }
            // A reply with no JSON in it names no claim to fix, so it gets no second round.
            let reasons = LookupResult.diagnose(error.content, query: query)
            guard !reasons.isEmpty else { throw error.error }
            let correction = try lookupRequest(
                query, config: config, correcting: error.content, reasons: reasons)
            switch try await attemptLookup(
                correction, query: query, title: L10n.shared.string("%@ (corrected)", title),
                config: config)
            {
            case .success(let result): return result
            case .failure(let retried): throw retried.error
            }
        }
    }

    /// Sends one lookup and parses it; the parse failure carries the content back for correction.
    private func attemptLookup(
        _ request: ModelRequest, query: LookupQuery, title: String, config: ServiceConfig
    ) async throws -> Result<LookupResult, ContractError> {
        func parsed(_ content: String) -> Result<LookupResult, ContractError> {
            do {
                return .success(try LookupResult.parse(content, query: query))
            } catch {
                return .failure(ContractError(error: error, content: content))
            }
        }
        return try await perform(
            request, title: title, symbol: "magnifyingglass", submitted: query.text,
            config: config, parse: parsed)
    }

    func lookupRequest(_ query: LookupQuery, config: ServiceConfig) throws -> ModelRequest {
        try lookupRequest(query, config: config, correcting: nil, reasons: [])
    }

    /// Builds the lookup request. With `correcting`, the same data comes after the model's own rejected
    /// reply and the claims it got wrong, so only the model's answer changes between the two requests.
    func lookupRequest(
        _ query: LookupQuery, config: ServiceConfig, correcting reply: String? = nil,
        reasons: [String] = []
    ) throws -> ModelRequest {
        let pronunciation =
            query.pronunciation.map { "Use \($0) for pronunciation." }
            ?? "Use kana for Japanese, pinyin for Chinese and IPA for other languages."
        let system = """
            Explain the text a reader selected. With a context, explain only what it means in that \
            context, adding usage only when needed; do not list other senses. With a null context, \
            give the general meaning. Write meaning and part_of_speech in \(query.definitionLanguage).
            Respond with one json object with keys text, language, definition_language, meaning, \
            lemma, pronunciation, part_of_speech. Every key must be present; a field that does not \
            apply or is uncertain is null, not missing. text must equal the selected text exactly. \
            language is the BCP 47 tag of the text, or null if unknown\
            \(query.language.map { "; it is \($0)" } ?? ""). definition_language is \
            \(query.definitionLanguage). lemma is the dictionary form only when it applies and is \
            certain, else null. \(pronunciation) Use null for any field that does not apply or is \
            uncertain. When the text is a whole sentence, pronunciation and part_of_speech must be null. \
            \(ModelPrompts["lookupExample"])
            """
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "text": query.text, "context": query.context as Any? ?? NSNull(),
                "selection_start": query.offset as Any? ?? NSNull(),
                "language": query.language as Any? ?? NSNull(),
            ], options: .sortedKeys)
        let user = String(decoding: payload, as: UTF8.self)
        let turns: [ModelTurn]
        if let reply {
            let problems =
                reasons.isEmpty
                ? "It does not satisfy the contract."
                : "These claims were wrong: " + reasons.joined(separator: "; ") + "."
            turns = [
                .user("Selected text, context and language, as data:\n\(user)"),
                .assistant(reply),
                .user(
                    """
                    That reply was rejected. \(problems)
                    Reply again with only the one json object, every key present and every other \
                    claim unchanged.
                    """),
            ]
        } else {
            turns = [.user(user)]
        }
        return ModelRequest(
            model: config.model, system: system, turns: turns,
            format: format(name: "lookup", schema: LookupResult.providerSchema, config: config),
            effort: config.effort, customEffort: config.customEffort,
            supportedEfforts: config.supportedEfforts)
    }

    /// The model list an HTTP service offers, in its own protocol's shape; a local agent lists its
    /// models through its own command instead (`LocalAgent.models`). One page is read, sized to hold
    /// every model a service lists today.
    func listModels(
        baseURL: URL, apiKey: String, provider: Provider = .openAICompatible
    ) async throws -> [String] {
        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(
                url: baseURL.appending(path: "models").appending(queryItems: [
                    URLQueryItem(name: "limit", value: "1000")
                ]))
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(AnthropicBackend.apiVersion, forHTTPHeaderField: "anthropic-version")
        case .gemini:
            request = URLRequest(
                url: baseURL.appending(path: "models").appending(queryItems: [
                    URLQueryItem(name: "pageSize", value: "1000")
                ]))
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .openAICompatible, .openAIResponses, .claudeCode, .codexCLI:
            request = URLRequest(url: baseURL.appending(path: "models"))
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let data = try await HTTPBackend.send(request, transport: transport)
        if provider == .gemini {
            // Gemini names a model `models/<id>` and also lists embedding models the app cannot use.
            guard let list = try? JSONDecoder().decode(GeminiModelList.self, from: data) else {
                throw ModelError.format
            }
            return (list.models ?? [])
                .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? true }
                .map { $0.name.replacingOccurrences(of: "models/", with: "") }
        }
        guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
            throw ModelError.format
        }
        return list.data.map(\.id)
    }

    /// Sends one request and hands the finished exchange to the debug capture whatever the outcome,
    /// then parses the answer. Every request type goes through here so none is silently left off the
    /// debug page, and no caller knows which backend ran it.
    private func perform<T>(
        _ request: ModelRequest, title: String, symbol: String, submitted: String,
        config: ServiceConfig, parse: (String) throws -> T
    ) async throws -> T {
        let backend = config.provider.backend(transport: transport, agent: localAgent)
        let capture = capture
        let records = capture.isEnabled()
        var response: String?
        var failure: String?
        var failureKind: ModelError.Kind?
        // The record is handed off, not awaited: diagnostics must never delay or fail a request.
        defer {
            if records {
                let exchange = DebugExchange(
                    title: title, symbol: symbol, request: backend.describe(request, config: config),
                    submitted: submitted, response: response, failure: failure,
                    failureKind: failureKind)
                let record = capture.record
                Task { await record(exchange) }
            }
        }
        do {
            let content = try await backend.complete(request, config: config)
            response = content
            return try parse(content)
        } catch {
            failure = (error as? ModelError)?.message ?? error.localizedDescription
            failureKind = (error as? ModelError)?.kind
            // A failed status still answered with a body, and that body is the diagnosis. A reply that
            // arrived and failed to parse keeps the reply it already has.
            if let detail = (error as? ModelError)?.diagnosticBody { response = detail }
            throw error
        }
    }

    func translationRequest(
        text: String, operation: Operation = .translate, to targetLanguage: String?,
        config: ServiceConfig
    ) throws -> ModelRequest {
        let task =
            targetLanguage.map { "Operation: translate. Target language: \($0)." }
            ?? "Operation: polish. target_language must equal source_language."
        let system = """
            \(promptForOperation(operation))

            \(task)
            Respond with one json object with keys source_language, target_language and segments \
            (array of {source, target}). Concatenated sources must equal the user message exactly.
            Example json: {"source_language":"en","target_language":"zh-Hans",\
            "segments":[{"source":"...","target":"..."}]}
            """
        // Without schema support the prompt above must mention "json" and spell out the shape.
        return ModelRequest(
            model: config.model, system: system, turns: [.user(text)],
            format: format(
                name: operation == .translate ? "translation" : "polish",
                schema: TranslationResult.providerSchema, config: config),
            effort: config.effort, customEffort: config.customEffort,
            supportedEfforts: config.supportedEfforts)
    }
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
            var refusal: String?
        }
        var message: Message
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    var choices: [Choice]
}

struct ModelList: Decodable {
    struct Model: Decodable { var id: String }
    var data: [Model]
}

struct GeminiModelList: Decodable {
    struct Model: Decodable {
        var name: String
        var supportedGenerationMethods: [String]?
    }
    var models: [Model]?
}
