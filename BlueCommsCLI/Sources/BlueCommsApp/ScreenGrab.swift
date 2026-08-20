//
//  ScreenGrab.swift
//
//  Why this file exists:
//    The Screenshot button in the composer. There is no separate "image
//    protocol" — we write a PNG and send it through the same file path as Attach.
//
//  Needs Screen Recording on recent macOS or CGDisplayCreateImage returns nil.
//

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ScreenGrab {
    /// Capture the main display to a timestamped PNG in /tmp. Nil if permission is denied.
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
