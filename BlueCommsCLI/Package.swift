// swift-tools-version: 6.1

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
