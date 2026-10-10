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
        let compact = size(CompactProcessingView(summary: "Hello there", status: "翻译中…", stop: {}))
        let notice = size(CompactNoticeView(message: "未能读取到文字"))
        #expect(compact.width == PanelMetrics.width)
        #expect(notice.width == PanelMetrics.width)
        #expect(compact.width == notice.width)
        #expect(compact.height == 110)
        let failed = size(
            CompactNoticeView(message: "连接失败", summary: "Hello", retry: {}, close: {}))
        #expect(failed.width == compact.width)
        #expect(failed.height == 110)
    }
    @Test func segmentedActionKeepsImageAndTextAndInvokesTheChosenAction() throws {
        var calls = 0
        let host = NSHostingController(
            rootView: PanelSegmentedControl(items: [
                .init(title: "翻译中…", symbol: "translate", action: {}),
                .init(title: "", symbol: "xmark", action: { calls += 1 }, accessibilityLabel: "取消处理"),
            ]))
        host.view.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> NSSegmentedControl? {
            if let control = view as? NSSegmentedControl { return control }
            return view.subviews.lazy.compactMap(find).first
        }
        let control = try #require(find(host.view))
        #expect(control.trackingMode == .momentary)
        #expect(control.segmentDistribution == .fit)
        // The title is drawn into the segment image, so it keeps its color in the inactive panel.
        #expect(control.image(forSegment: 0)?.accessibilityDescription == "翻译中…")
        #expect(control.image(forSegment: 0)?.isTemplate == false)
        #expect(control.width(forSegment: 1) == 36)
        #expect(control.subviews.compactMap { $0 as? NSBox }.contains { $0.boxType == .separator })
        // Momentary selection exists only during native tracking; simulate that selection for dispatch.
        control.trackingMode = .selectOne
        control.selectedSegment = 1
        control.sendAction(control.action, to: control.target)
        #expect(calls == 1)
    }

}
