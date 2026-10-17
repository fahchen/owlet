import Foundation
import Observation

/// This launch's lookups, shared by every reading area. Memory only and bounded: quitting forgets
/// them, and nothing here is a query history.
@MainActor @Observable
final class LookupStore {
    enum Entry: Equatable {
        case loading
        /// The explanation is arriving piece by piece and is still in flight; shown in the card so
        /// the wait reads. It is not an answer — it was never validated — so nothing collects or
        /// reuses it (BDR-0017).
        case receiving(String)
        case success(LookupResult)
        case failure(String)
    }

    /// Enough for a reading session; the oldest settled lookup goes first.
    static let capacity = 200

    private(set) var entries: [LookupQuery: Entry] = [:]
    /// Settled-first eviction order, oldest at the front.
    private var order: [LookupQuery] = []
    private let client: ModelClient
    private let config: () -> ServiceConfig?
    private let defaults: UserDefaults

    /// `ModelClient.live` so a lookup streams while still answering (BDR-0017); a test passes a
    /// client of its own and the lookup follows it.
    init(
        client: ModelClient = ModelClient.live,
        config: @escaping () -> ServiceConfig? = SettingsStore.currentConfig,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.config = config
        self.defaults = defaults
    }

    /// Stamps the current model and reading-notation settings, so a changed setting can never hit
    /// an older answer.
    func stamped(_ query: LookupQuery) -> LookupQuery {
        var query = query
        query.service = config().map(LookupQuery.service) ?? ""
        query.pronunciation = query.language.map {
            SettingsStore.pronunciationSystem(for: $0, in: defaults).rawValue
        }
        return query
    }

    /// An explicit lookup. A finished, failed or running lookup for the same query is shown as it
    /// is; a compatible answer from another sentence is offered instead of asking. Returns that
    /// other sentence's query, if any.
    @discardableResult
    func open(_ query: LookupQuery) -> LookupQuery? {
        if entries[query] != nil { return nil }
        if let other = otherSentence(for: query) { return other }
        request(query)
        return nil
    }

    /// Sends the query unless the same one is already running; Retry and Look Up in This Sentence land here.
    func request(_ query: LookupQuery) {
        guard !inFlight(entries[query]) else { return }
        guard let config = config() else {
            store(.failure(L10n.shared.string("The model service is not configured")), for: query)
            return
        }
        store(.loading, for: query)
        let client = client
        Task {
            let entry: Entry
            do {
                entry = .success(
                    // The enclosing Task already owns `self` until the lookup completes, so a
                    // weak capture here would only diverge from it.
                    try await client.lookup(query, config: config) { accumulated in
                        await self.receive(accumulated, for: query)
                    })
            } catch {
                entry = .failure((error as? ModelError)?.message ?? error.localizedDescription)
            }
            // A later answer only ever fills its own query, so it cannot replace another card.
            self.store(entry, for: query)
        }
    }

    /// Whether `entry` is a request still answering: loading or a stream still arriving, both of
    /// which a new request replaces rather than duplicates.
    private func inFlight(_ entry: Entry?) -> Bool {
        switch entry {
        case .loading, .receiving: true
        default: false
        }
    }

    /// One step of the arriving stream: the explanation text the accumulated reply has completed.
    /// Everything else is dropped, and a query that is no longer the one running sees nothing.
    private func receive(_ accumulated: String, for query: LookupQuery) {
        guard inFlight(entries[query]) else { return }
        guard let meaning = PartialReply.meaning(from: accumulated) else { return }
        store(.receiving(meaning), for: query)
    }

    /// The newest answer for the same words in another real sentence, with every setting that
    /// shapes an answer unchanged. An unknown language or a context-free answer never qualifies.
    func otherSentence(for query: LookupQuery) -> LookupQuery? {
        guard query.context != nil, let language = query.language else { return nil }
        return order.last { other in
            guard case .success = entries[other] else { return false }
            return other.context != nil && other != query && other.text == query.text
                && other.language.map { LanguageTag.same($0, language) } == true
                && other.definitionLanguage == query.definitionLanguage
                && other.pronunciation == query.pronunciation && other.service == query.service
        }
    }

    private func store(_ entry: Entry, for query: LookupQuery) {
        entries[query] = entry
        order.removeAll { $0 == query }
        order.append(query)
        while order.count > Self.capacity,
            let index = order.firstIndex(where: { entries[$0] != .loading })
        {
            entries[order.remove(at: index)] = nil
        }
    }
}
