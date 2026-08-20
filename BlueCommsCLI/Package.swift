// swift-tools-version: 6.1
//
//  Package.swift
//
//  Why this file exists:
//    SwiftPM manifest. One package, four targets:
//      BlueCommsCore     — framing, crypto, Bonjour/AWDL, files (the radio)
//      BlueCommsCLI      — terminal
//      BlueCommsApp      — Mac window
//      BlueCommsSelfTest — XCTest is missing from Command Line Tools, so a
//                          normal executable that prints ok/FAIL
//
//  Info.plist is linked into the two user binaries (`-sectcreate __TEXT
//  __info_plist`) so macOS Local Network / Bonjour prompts work. Without
//  those keys, browse stays empty even with Wi-Fi on.
//

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let infoPlistPath = packageDirectory.appendingPathComponent("Sources/BlueCommsCLI/Info.plist").path
let appInfoPlistPath = packageDirectory.appendingPathComponent("Sources/BlueCommsApp/Info.plist").path

let package = Package(
    name: "BlueCommsCLI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "BlueCommsCore"
        ),
        .executableTarget(
            name: "BlueCommsCLI",
            dependencies: ["BlueCommsCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath,
                ])
            ]
        ),
        .executableTarget(
            name: "BlueCommsApp",
            dependencies: ["BlueCommsCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", appInfoPlistPath,
                ])
            ]
        ),
        .executableTarget(
            name: "BlueCommsSelfTest",
            dependencies: ["BlueCommsCore"]
        ),
    ]
)
