//
//  BlueCommsApp.swift
//
//  Why this file exists:
//    `swift run BlueCommsApp` needs a @main App. This is that entry point.
//    Without it there is only the terminal client.
//
//  What it does:
//    • Builds ChatStore (identity + history) before the window appears.
//    • Shows ContentView, or a plain error if disk/identity failed.
//    • Starts the radio after the window exists so launch stays fast.
//    • Forces the process into the Dock. `swift run` is not a real .app
//      bundle, so without this the window can open blank or behind other apps.
//
//  PR #2 added the window. PR #6 is why start() is in onAppear (not init)
//  and why bringForward() exists.
//

import AppKit
import SwiftUI

@main
struct BlueCommsMacApp: App {
    /// Shared by every view via .environmentObject.
    @StateObject private var store: ChatStore
    /// Non-nil means we could not load ~/.bluecomms. Window shows this text.
    private let launchError: String?

    init() {
        do {
            let created = try ChatStore()
            _store = StateObject(wrappedValue: created)
            launchError = nil
        } catch {
            // Identity/archive can fail (disk permissions). Show the error; do not fake a UI.
            _store = StateObject(wrappedValue: ChatStore.failed(error))
            launchError = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup("BlueComms") {
            if let launchError {
                Text("BlueComms could not start\n\(launchError)")
                    .padding(32)
                    .frame(minWidth: 520, minHeight: 240)
            } else {
                ContentView()
                    .environmentObject(store)
                    .frame(minWidth: 820, minHeight: 520)
                    .onAppear {
                        bringForward()
                        // After the window exists so launch stays fast. start() is once-only.
                        store.start()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                        store.stop()
                    }
            }
        }
        .defaultSize(width: 900, height: 600)
    }

    /// Unbundled binaries start as a background process; this makes the window visible.
    private func bringForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }
}
