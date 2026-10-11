import Foundation
import Testing

@testable import Owlet

/// A contract failure's recovery entry points at the prompt editor of the operation that failed, and
/// the routing is decided by the failure itself — never by its message, which is translated.
@MainActor
struct PromptRouteTests {
    private func makeController() -> PanelController {
        let model = TextProcessingModel(client: ModelClient(), config: { testConfig })
        return PanelController(
            model: model, defaults: UserDefaults(suiteName: "PromptRouteTests.\(UUID().uuidString)")!)
    }

    @Test func contractFailuresRouteToTheCurrentOperation() {
        let controller = makeController()
        controller.model.operation = .polish
        #expect(
            controller.promptSettingsOperation(
                for: .failure(ModelError.format.message, kind: .contract)) == .polish)
        controller.model.operation = .translate
        #expect(
            controller.promptSettingsOperation(
                for: .failure(ModelError.format.message, kind: .contract)) == .translate)
        // The mismatches are contract failures too: a prompt edit is what can address them.
        #expect(
            controller.promptSettingsOperation(
                for: .failure(ModelError.sourceMismatch.message, kind: .contract)) == .translate)
        #expect(
            controller.promptSettingsOperation(
                for: .failure(
                    ModelError.targetMismatch(requested: "zh-Hans", returned: "ja").message,
                    kind: .contract)) == .translate)
    }

    @Test func otherNoticesDoNotRouteToPromptSettings() {
        let controller = makeController()
        #expect(controller.promptSettingsOperation(for: .missingConfig) == nil)
        #expect(
            controller.promptSettingsOperation(
                for: .failure(ModelError.unauthorized.message, kind: .service)) == nil)
        #expect(controller.promptSettingsOperation(for: .permission) == nil)
    }

    /// The point of carrying the kind: the same wording must be able to route either way, which is what
    /// a translated interface makes possible.
    @Test func theRouteFollowsTheKindAndNotTheWording() {
        let controller = makeController()
        let message = ModelError.format.message
        #expect(
            controller.promptSettingsOperation(for: .failure(message, kind: .contract)) != nil)
        #expect(controller.promptSettingsOperation(for: .failure(message, kind: .service)) == nil)
    }

    /// Every failure names its own kind, so nothing has to read a message to decide.
    @Test func everyModelFailureCarriesItsKind() {
        #expect(ModelError.format.kind == .contract)
        #expect(ModelError.sourceMismatch.kind == .contract)
        #expect(ModelError.targetMismatch(requested: "en", returned: "ja").kind == .contract)
        #expect(ModelError.unauthorized.kind == .connection)
        #expect(ModelError.network("x").kind == .connection)
        #expect(ModelError.http(500).kind == .connection)
        #expect(ModelError.emptyResponse.kind == .service)
        #expect(ModelError.truncated.kind == .service)
        #expect(ModelError.refused.kind == .service)
    }
}
