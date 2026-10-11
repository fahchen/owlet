import AppKit
import Foundation
import UniformTypeIdentifiers

/// The exported snapshot of the notebook; a version field lets a later release change the shape
/// without guessing which file it is reading.
struct VocabularyExportDocument: Codable, Equatable {
    struct Context: Codable, Equatable {
        var source: String
        var polishBefore: String?
        var polishAfter: String?
    }

    struct Entry: Codable, Equatable {
        var expression: String
        var language: String
        var meaning: String
        /// The dictionary form when a recommendation supplied one (BDR-0009); empty otherwise.
        var lemma: String
        var contexts: [Context]
    }

    var version: Int
    var entries: [Entry]
}

/// Turns the notebook into a file; it only reads the store, so a failed or cancelled write can
/// never change what the user has collected.
enum VocabularyExport {
    /// Builds the document, keeping every context and the polish pair of each one.
    static func document(_ entries: [VocabularyEntry]) -> VocabularyExportDocument {
        VocabularyExportDocument(
            version: 2,
            entries: entries.map { entry in
                VocabularyExportDocument.Entry(
                    expression: entry.expression,
                    language: entry.language,
                    meaning: entry.meaning,
                    lemma: entry.lemma,
                    contexts: entry.contexts.map { context in
                        VocabularyExportDocument.Context(
                            source: context.source,
                            polishBefore: context.polishBefore,
                            polishAfter: context.polishAfter)
                    })
            })
    }

    /// Encodes pretty-printed UTF-8 JSON, which keeps Chinese and Japanese literal and readable.
    static func data(_ entries: [VocabularyEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document(entries))
    }

    /// Writes the whole notebook to one file.
    static func write(_ entries: [VocabularyEntry], to url: URL) throws {
        try data(entries).write(to: url, options: .atomic)
    }
}

/// Runs the export gesture: the file panel is the only thing a cancel or a write failure touches.
@MainActor @Observable
final class NotebookExporter {
    enum Status: Equatable {
        case idle
        case saved(URL)
        case cancelled
        case failed(String)
    }

    private(set) var status: Status = .idle
    private let chooseDestination: @MainActor () -> URL?

    init(chooseDestination: @escaping @MainActor () -> URL? = NotebookExporter.presentSavePanel) {
        self.chooseDestination = chooseDestination
    }

    /// Writes every entry to the chosen file; cancelling leaves the notebook exactly as it was.
    func export(_ entries: [VocabularyEntry]) {
        guard let url = chooseDestination() else {
            status = .cancelled
            return
        }
        do {
            try VocabularyExport.write(entries, to: url)
            status = .saved(url)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Clears the last result so the alert that reported it can be dismissed.
    func reset() {
        status = .idle
    }

    private static func presentSavePanel() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "生词本.json"
        panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }
}
