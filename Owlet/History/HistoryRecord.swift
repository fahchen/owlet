import Foundation
import SwiftData

/// One finished translate or polish result; it copies its own text and language, so history never
/// points at the notebook or a selection and deleting it cannot reach either.
@Model
final class HistoryRecord {
    /// The producing operation's raw value, kept as text so the record stays decoupled from the enum.
    var operation: String = Operation.translate.rawValue
    var source: String = ""
    var result: String = ""
    var language: String = ""
    var createdAt: Date = Date()
    /// The screenshot a screen region translation read its source from (BDR-0019); outside the store
    /// file, and deleted with the record.
    @Attribute(.externalStorage) var sourceImage: Data?

    init(
        operation: Operation, source: String, result: String, language: String,
        createdAt: Date = Date(), sourceImage: Data? = nil
    ) {
        self.operation = operation.rawValue
        self.source = source
        self.result = result
        self.language = language
        self.createdAt = createdAt
        self.sourceImage = sourceImage
    }

    /// The operation to show; only the two known raw values are ever written.
    var operationKind: Operation {
        Operation(rawValue: operation) ?? .translate
    }
}

extension HistoryRecord {
    /// BDR-0005 for a record: a translation is explained in its target, a polish in the mapped target
    /// of its language. A translation's source language was never stored, so it stays unknown.
    func lookupOrigins(mapping: TargetMapping) -> (source: LookupOrigin, result: LookupOrigin) {
        guard operationKind == .translate else {
            let polish = LookupOrigin.result(of: .polish, languages: (language, language), mapping: mapping)
            return (polish, polish)
        }
        return (
            LookupOrigin(language: nil, definitionLanguage: language),
            LookupOrigin(language: language, definitionLanguage: language)
        )
    }
}
