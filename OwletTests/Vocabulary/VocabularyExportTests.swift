import Foundation
import SwiftData
import Testing

@testable import Owlet

@MainActor
struct VocabularyExportTests {
    func makeStore() throws -> VocabularyStore {
        let schema = Schema([VocabularyEntry.self, VocabularyContext.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return VocabularyStore(container: try ModelContainer(for: schema, configurations: [config]))
    }

    /// A notebook with the awkward content an export has to keep: mixed languages, a second context,
    /// a polish pair, an embedded newline and quotes.
    func notebook() throws -> VocabularyStore {
        let store = try makeStore()
        let english = try store.collect(
            VocabularyDraft(
                expression: "take a \"step\" back", language: "en",
                context: "Let's take a step back.\nLook at the bigger picture.",
                polishBefore: "Let's take a step back.", polishAfter: "Let's take a step back and look."))
        try store.update(english, expression: english.expression, meaning: "退一步，从新的角度重新审视。")
        english.contexts.append(VocabularyContext(source: "日本語の文。", polishBefore: nil, polishAfter: nil))
        try store.save()
        let japanese = try store.collect(
            VocabularyDraft(
                expression: "手紙", language: "ja", context: "手紙を書きます。", polishBefore: nil,
                polishAfter: nil))
        try store.update(japanese, expression: japanese.expression, meaning: "信。")
        return store
    }

    @Test func encodedDocumentKeepsEveryFieldContextAndComparison() throws {
        let store = try notebook()
        let data = try VocabularyExport.data(try store.entries())
        let decoder = JSONDecoder()
        let document = try decoder.decode(VocabularyExportDocument.self, from: data)
        #expect(document.version == 1)
        #expect(document.entries.count == 2)

        let japanese = try #require(document.entries.first { $0.language == "ja" })
        #expect(japanese.expression == "手紙")
        #expect(japanese.meaning == "信。")
        #expect(japanese.contexts.count == 1)
        #expect(japanese.contexts.first?.source == "手紙を書きます。")
        #expect(japanese.contexts.first?.polishBefore == nil)

        let english = try #require(document.entries.first { $0.language == "en" })
        #expect(english.expression == "take a \"step\" back")
        #expect(english.meaning == "退一步，从新的角度重新审视。")
        #expect(english.contexts.count == 2)
        let collected = try #require(
            english.contexts.first { $0.polishAfter != nil })
        #expect(collected.polishBefore == "Let's take a step back.")
        #expect(collected.source.contains("\n"))
        #expect(english.contexts.contains { $0.source == "日本語の文。" })
    }

    @Test func theFileIsReadableUTF8() throws {
        let store = try notebook()
        let data = try VocabularyExport.data(try store.entries())
        let text = try #require(String(data: data, encoding: .utf8))
        // Literal CJK proves the encoder did not fall back to \u escapes.
        #expect(text.contains("手紙"))
        #expect(text.contains("退一步，从新的角度重新审视。"))
    }

    @Test func aSuccessfulExportWritesTheChosenFile() throws {
        let store = try notebook()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("owlet-export-\(UUID().uuidString).json")
        let exporter = NotebookExporter(chooseDestination: { url })
        exporter.export(try store.entries())
        #expect(exporter.status == .saved(url))
        let decoded = try JSONDecoder().decode(
            VocabularyExportDocument.self, from: Data(contentsOf: url))
        #expect(decoded.entries.count == (try store.entries().count))
    }

    @Test func cancellingLeavesTheNotebookUntouched() throws {
        let store = try notebook()
        let before = try store.entries().map(\.expression)
        let exporter = NotebookExporter(chooseDestination: { nil })
        exporter.export(try store.entries())
        #expect(exporter.status == .cancelled)
        #expect(try store.entries().map(\.expression) == before)
    }

    @Test func aFailedWriteLeavesTheNotebookUntouched() throws {
        let store = try notebook()
        let before = try store.entries().map(\.expression)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("owlet-missing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("out.json")
        let exporter = NotebookExporter(chooseDestination: { url })
        exporter.export(try store.entries())
        guard case .failed = exporter.status else {
            Issue.record("expected a failed write, got \(exporter.status)")
            return
        }
        #expect(try store.entries().map(\.expression) == before)
    }
}
