import AppKit
import SwiftUI
import Testing

@testable import Owlet

/// One width for both panel surfaces, and the write-back still takes the keyboard first.
@MainActor
struct PanelMetricsTests {
    let range = SelectedRange(location: 0, length: 5)

    func size(_ view: some View) -> NSSize {
        let host = NSHostingController(rootView: view)
        // The panel drives its window from this, so the test measures the same thing it does.
        host.sizingOptions = .preferredContentSize
        host.view.layoutSubtreeIfNeeded()
        return host.preferredContentSize
    }

    /// The compact strip and the expanded panel must be the same width, so expanding only grows the
    /// panel's height.
    @Test func bothSurfacesAreTheSameWidth() {
        let compact = size(ProcessingStrip(summary: "Hello there", status: "翻译中…", stop: {}))
        let notice = size(NoticeStrip(message: "未能读取到文字") { Button("手动输入") {} })
        #expect(compact.width == PanelMetrics.width)
        #expect(notice.width == PanelMetrics.width)
        #expect(compact.width == notice.width)
    }
}
