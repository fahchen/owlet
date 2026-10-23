import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Text from a rectangle of the screen: the system's own interactive capture picks the rectangle and
/// Vision reads it on this Mac (BDR-0019).
enum ScreenRegion {
    /// Asks once; macOS only grants a new permission to a relaunched process, so a first request
    /// still answers false and the notice explains where to turn it on.
    static func hasAccess() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    static let permissionSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    /// Runs `screencapture -i`: the system crosshair, Esc to cancel, Space for a window. Returns the
    /// PNG, or nil when the user cancelled (no file is written then).
    static func capture() async throws -> Data? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "owlet-region-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-o", url.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        return try? Data(contentsOf: url)
    }

    /// The copy that is kept: Vision reads the full capture, but the panel and history show it at
    /// most 160pt high, so a 1280px JPEG is enough. Falls back to the original if ImageIO fails.
    static func keptCopy(of image: Data, maxPixels: Int = 1280, quality: Double = 0.6) -> Data {
        guard let source = CGImageSourceCreateWithData(image as CFData, nil),
            let scaled = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return image }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return image }
        CGImageDestinationAddImage(
            destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return image }
        return output as Data
    }

    /// The recognised lines, top to bottom; empty when there is no text or Vision fails.
    static func recognize(_ image: Data) async -> String {
        var request = RecognizeTextRequest()
        request.automaticallyDetectsLanguage = true
        guard let observations = try? await request.perform(on: image) else { return "" }
        return text(from: observations.map { ($0.transcript, $0.boundingBox.cgRect.maxY) })
    }

    /// Joins lines by their top edge in Vision's lower-left space.
    // ponytail: top-down only, no column detection; the model orders the text (BDR-0019).
    static func text(from lines: [(text: String, top: CGFloat)]) -> String {
        lines.sorted { $0.top > $1.top }
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
