import AppKit
import Testing

@testable import Owlet

struct ScreenRegionTests {
    /// Vision's space has its origin at the bottom, so the highest line is read first.
    @Test func linesAreJoinedTopToBottom() {
        let text = ScreenRegion.text(from: [("second", 0.5), ("first", 0.9), (" ", 0.7), ("third", 0.1)])
        #expect(text == "first\nsecond\nthird")
    }

    /// The real Vision path on a picture drawn here, so no screen is captured.
    @Test func recognisesTextInAnImage() async throws {
        let png = try #require(Self.picture(of: ["Could you send me", "the report?"]))
        let text = await ScreenRegion.recognize(png)
        #expect(text == "Could you send me\nthe report?")
    }

    /// Black text on white, in two lines, as a PNG.
    static func picture(of lines: [String]) -> Data? {
        let size = NSSize(width: 640, height: 80 * CGFloat(lines.count) + 40)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: NSPoint(x: 24, y: 24 + 80 * CGFloat(index)),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            }
            return true
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
