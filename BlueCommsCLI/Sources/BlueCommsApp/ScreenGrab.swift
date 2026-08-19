import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ScreenGrab {
    static func savePNG() -> URL? {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Screenshot \(formatter.string(from: Date())).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }
}
