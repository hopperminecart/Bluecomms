import SwiftUI

@main
struct BlueCommsMacApp: App {
    @StateObject private var store: ChatStore

    init() {
        let demo = CommandLine.arguments.contains("--demo")
        let created: ChatStore
        do {
            created = try ChatStore(demo: demo)
        } catch {
            fatalError("Failed to start BlueComms: \(error)")
        }
        _store = StateObject(wrappedValue: created)
    }

    var body: some Scene {
        WindowGroup("BlueComms") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
