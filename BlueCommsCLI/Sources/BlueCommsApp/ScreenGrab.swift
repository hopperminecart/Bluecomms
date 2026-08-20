import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Grabs the main display. Needs Screen Recording permission on recent macOS.
enum ScreenGrab {
    static func savePNG() -> URL? {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { return nil }
        let stamp = Date().formatted(date: .numeric, time: .standard)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshot \(stamp).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? url : nil
    }
}
