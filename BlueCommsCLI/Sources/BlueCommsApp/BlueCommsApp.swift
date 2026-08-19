import AppKit
import SwiftUI

@main
struct BlueCommsMacApp: App {
    @StateObject private var store: ChatStore
    private let launchError: String?

    init() {
        let demo = CommandLine.arguments.contains("--demo")
        do {
            let created = try ChatStore(demo: demo)
            _store = StateObject(wrappedValue: created)
            launchError = nil
        } catch {
            _store = StateObject(wrappedValue: ChatStore.placeholder)
            launchError = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup("BlueComms") {
            Group {
                if let launchError {
                    VStack(spacing: 12) {
                        Text("BlueComms could not start")
                            .font(.title2.weight(.semibold))
                        Text(launchError)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(32)
                    .frame(minWidth: 520, minHeight: 240)
                } else {
                    ContentView()
                        .environmentObject(store)
                        .frame(minWidth: 820, minHeight: 520)
                        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                            store.stop()
                        }
                }
            }
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
