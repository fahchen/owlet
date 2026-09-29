import AppKit
import Foundation
import Testing

@testable import Owlet

struct PanelPlacementTests {
    let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let size = NSSize(width: 400, height: 100)

    @Test func topLeftFrameStaysInsideVisibleFrame() {
        let size = NSSize(width: 560, height: 300)
        #expect(
            PanelPlacement.frame(size: size, topLeft: NSPoint(x: 100, y: 700), within: visible)
                == NSRect(x: 100, y: 400, width: 560, height: 300))
        #expect(
            PanelPlacement.frame(size: size, topLeft: NSPoint(x: 900, y: 100), within: visible)
                == NSRect(x: 440, y: 0, width: 560, height: 300))
        #expect(
            PanelPlacement.frame(
                size: NSSize(width: 560, height: 1200), topLeft: NSPoint(x: -50, y: 900), within: visible)
                == NSRect(x: 0, y: 0, width: 560, height: 800))
    }

    @Test func fixedDefaultsToUpperCenter() {
        #expect(
            PanelPlacement.frame(size: size, anchor: .topCenter(nil), within: visible)
                == NSRect(x: 300, y: 540, width: 400, height: 100))
    }

    @Test func savedFixedSpotIsReusedAndCentered() {
        #expect(
            PanelPlacement.frame(size: size, anchor: .topCenter(NSPoint(x: 400, y: 500)), within: visible)
                == NSRect(x: 200, y: 400, width: 400, height: 100))
    }

    /// A spot saved on a display that is gone is pulled into the current visible frame.
    @Test func savedFixedSpotIsClampedAfterDisplayChange() {
        let secondary = NSRect(x: 1000, y: 0, width: 800, height: 600)
        #expect(
            PanelPlacement.frame(size: size, anchor: .topCenter(NSPoint(x: 2600, y: 1400)), within: secondary)
                == NSRect(x: 1400, y: 500, width: 400, height: 100))
    }

    @Test func followPlacesBelowSelection() {
        let selection = NSRect(x: 120, y: 500, width: 80, height: 20)
        #expect(
            PanelPlacement.frame(size: size, anchor: .below(selection), within: visible)
                == NSRect(x: 120, y: 500 - PanelPlacement.gap - 100, width: 400, height: 100))
    }

    @Test func followFlipsAboveWhenNoRoomBelow() {
        let selection = NSRect(x: 120, y: 50, width: 80, height: 20)
        #expect(
            PanelPlacement.frame(size: size, anchor: .below(selection), within: visible)
                == NSRect(x: 120, y: 70 + PanelPlacement.gap, width: 400, height: 100))
    }

    /// With no room either way the panel stays below and is clamped inside the visible frame.
    @Test func followClampsWhenNoRoomEitherWay() {
        let tall = NSSize(width: 400, height: 500)
        let selection = NSRect(x: 900, y: 300, width: 80, height: 200)
        #expect(
            PanelPlacement.frame(size: tall, anchor: .below(selection), within: visible)
                == NSRect(x: 600, y: 0, width: 400, height: 500))
    }

    @Test func followFallsBackToMouse() {
        let mouse = NSPoint(x: 10, y: 20)
        #expect(PanelPlacement.followAnchor(selectionBounds: nil, mouse: mouse) == .topLeft(mouse))
        let bounds = NSRect(x: 1, y: 2, width: 3, height: 4)
        #expect(PanelPlacement.followAnchor(selectionBounds: bounds, mouse: mouse) == .below(bounds))
    }

    @Test func axRectConvertsToAppKitCoordinates() {
        // AX: 100pt below the primary screen's top edge; AppKit: measured up from its bottom.
        #expect(
            PanelPlacement.appKitRect(
                fromAX: CGRect(x: 50, y: 100, width: 80, height: 20), primaryScreenHeight: 900)
                == NSRect(x: 50, y: 780, width: 80, height: 20))
        // A display above the primary one has negative AX y.
        #expect(
            PanelPlacement.appKitRect(
                fromAX: CGRect(x: 0, y: -300, width: 10, height: 10), primaryScreenHeight: 900)
                == NSRect(x: 0, y: 1190, width: 10, height: 10))
    }

    @Test func positionSettingPersists() {
        let suite = "PanelPlacementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SettingsStore.panelPosition(in: defaults) == .fixed)
        #expect(SettingsStore.panelFixedAnchor(in: defaults) == nil)
        defaults.set(PanelPosition.followSelection.rawValue, forKey: SettingsStore.panelPositionKey)
        #expect(SettingsStore.panelPosition(in: defaults) == .followSelection)
        SettingsStore.setPanelFixedAnchor(CGPoint(x: 12.5, y: 30), in: defaults)
        #expect(SettingsStore.panelFixedAnchor(in: defaults) == CGPoint(x: 12.5, y: 30))
    }
}
