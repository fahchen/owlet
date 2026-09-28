import Foundation
import Testing

@testable import Owlet

/// The format-error recovery entry points at the prompt editor of the operation that failed.
@MainActor
struct PromptRouteTests {
    private func makeController() -> PanelController {
        let model = TranslationModel(client: ModelClient(), config: { testConfig })
        return PanelController(
            model: model, defaults: UserDefaults(suiteName: "PromptRouteTests.\(UUID().uuidString)")!)
    }

    @Test func contractFailuresRouteToTheCurrentOperation() {
        let controller = makeController()
        controller.model.operation = .polish
        #expect(controller.promptSettingsOperation(for: .failure(ModelError.format.message)) == .polish)
        controller.model.operation = .translate
        #expect(
            controller.promptSettingsOperation(for: .failure(ModelError.format.message)) == .translate)
        // The mismatches are contract failures too: a prompt edit is what can address them.
        #expect(
            controller.promptSettingsOperation(for: .failure(ModelError.sourceMismatch.message))
                == .translate)
        #expect(
            controller.promptSettingsOperation(
                for: .failure(
                    ModelError.targetMismatch(requested: "zh-Hans", returned: "ja").message))
                == .translate)
    }

    @Test func otherNoticesDoNotRouteToPromptSettings() {
        let controller = makeController()
        #expect(controller.promptSettingsOperation(for: .missingConfig) == nil)
        #expect(
            controller.promptSettingsOperation(for: .failure(ModelError.unauthorized.message)) == nil)
        #expect(controller.promptSettingsOperation(for: .permission) == nil)
    }
}
