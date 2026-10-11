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
                expression: "跳ね上がっている", language: "ja", context: "物価が跳ね上がっている。",
                polishBefore: nil, polishAfter: nil, lemma: "跳ね上がる"))
        try store.update(japanese, expression: japanese.expression, meaning: "急剧上升。")
        return store
    }

    @Test func encodedDocumentKeepsEveryFieldContextAndComparison() throws {
        let store = try notebook()
        let data = try VocabularyExport.data(try store.entries())
        let decoder = JSONDecoder()
        let document = try decoder.decode(VocabularyExportDocument.self, from: data)
        #expect(document.version == 2)
        #expect(document.entries.count == 2)

        let japanese = try #require(document.entries.first { $0.language == "ja" })
        #expect(japanese.expression == "跳ね上がっている")
        #expect(japanese.meaning == "急剧上升。")
        // The dictionary form rides along with the form it was collected as (BDR-0009).
        #expect(japanese.lemma == "跳ね上がる")
        #expect(japanese.contexts.count == 1)
        #expect(japanese.contexts.first?.source == "物価が跳ね上がっている。")
        #expect(japanese.contexts.first?.polishBefore == nil)

        let english = try #require(document.entries.first { $0.language == "en" })
        #expect(english.expression == "take a \"step\" back")
        #expect(english.meaning == "退一步，从新的角度重新审视。")
        // A region that only has text leaves the lemma empty rather than inventing one.
        #expect(english.lemma.isEmpty)
        #expect(english.contexts.count == 2)
        let collected = try #require(
            english.contexts.first { $0.polishAfter != nil })
        #expect(collected.polishBefore == "Let's take a step back.")
        #expect(collected.source.contains("\n"))
        #expect(english.contexts.contains { $0.source == "日本語の文。" })
    }

    @Test func exportKeepsAnAppendedContext() throws {
        let store = try makeStore()
        _ = try store.collect(
            VocabularyDraft(
                expression: "follow up", language: "en", context: "I will follow up tomorrow.",
                polishBefore: nil, polishAfter: nil))
        _ = try store.collect(
            VocabularyDraft(
                expression: "follow up", language: "en", context: "She will follow up next week.",
                polishBefore: nil, polishAfter: nil))
        let document = VocabularyExport.document(try store.entries())
        // The export reads the same entry, so both collected sentences reach the file.
        #expect(document.entries.count == 1)
        #expect(
            Set(document.entries.first?.contexts.map(\.source) ?? []) == [
                "I will follow up tomorrow.", "She will follow up next week.",
            ])
    }

    @Test func theFileIsReadableUTF8() throws {
        let store = try notebook()
        let data = try VocabularyExport.data(try store.entries())
        let text = try #require(String(data: data, encoding: .utf8))
        // Literal CJK proves the encoder did not fall back to \u escapes.
        #expect(text.contains("跳ね上がっている"))
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
