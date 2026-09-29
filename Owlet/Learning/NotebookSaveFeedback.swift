import SwiftUI

/// In-place result of a collect action, shown next to the result so the user is not pulled away.
struct NotebookSaveFeedback: View {
    let collection: CollectionAction
    let openNotebook: (() -> Void)?

    var body: some View {
        switch collection.status {
        case .saved:
            Label("已加入生词本", systemImage: "checkmark")
            if let openNotebook {
                Button("查看", action: openNotebook).buttonStyle(.glass)
            }
        case .filling:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("补充中文释义中")
            }
        case .meaningFailed(let entry, let message):
            Label("释义补充失败：\(message)", systemImage: "exclamationmark.triangle")
            Button("重试") { collection.fillMeaning(for: entry) }.buttonStyle(.glass)
        case .saveFailed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
        case .idle:
            EmptyView()
        }
    }
}
