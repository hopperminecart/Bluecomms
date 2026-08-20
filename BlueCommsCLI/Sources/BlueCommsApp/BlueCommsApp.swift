import AppKit
import SwiftUI

/// Mac window. `swift run` is not a real .app, so we force the process to the foreground.
@main
struct BlueCommsMacApp: App {
    @StateObject private var store: ChatStore
    private let launchError: String?

    init() {
        do {
            let created = try ChatStore()
            _store = StateObject(wrappedValue: created)
            launchError = nil
        } catch {
            // ChatStore requires a real store; show the error instead of a fake UI.
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
                        store.start()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                        store.stop()
                    }
            }
        }
        .defaultSize(width: 900, height: 600)
    }

    private func bringForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }
}
