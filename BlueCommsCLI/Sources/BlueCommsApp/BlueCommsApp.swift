import AppKit
import SwiftUI

@main
struct BlueCommsMacApp: App {
    @StateObject private var store: ChatStore
    @StateObject private var harness = PairHarness()
    private let launchError: String?
    private let windowTitle: String
    private let sendFiles: [URL]
    private let pairTest: Bool
    private let demoTransfer: Bool

    init() {
        let args = CommandLine.arguments
        let demo = args.contains("--demo")
        let pair = args.contains("--pair-test")
        pairTest = pair
        demoTransfer = args.contains("--demo-transfer")
        var dataDirectory: URL?
        var files: [URL] = []
        var title = "BlueComms"
        if let index = args.firstIndex(of: "--data-dir"), args.index(after: index) < args.endIndex {
            dataDirectory = URL(fileURLWithPath: args[args.index(after: index)], isDirectory: true)
        }
        if let index = args.firstIndex(of: "--name"), args.index(after: index) < args.endIndex {
            title = "BlueComms — \(args[args.index(after: index)])"
        }
        var cursor = args.makeIterator()
        while let item = cursor.next() {
            if item == "--send-file", let path = cursor.next() {
                files.append(URL(fileURLWithPath: path))
            }
        }
        windowTitle = title
        sendFiles = files
        do {
            if pair {
                _store = StateObject(wrappedValue: ChatStore.placeholder)
            } else {
                let created = try ChatStore(demo: demo, dataDirectory: dataDirectory)
                _store = StateObject(wrappedValue: created)
            }
            launchError = nil
        } catch {
            _store = StateObject(wrappedValue: ChatStore.placeholder)
            launchError = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup(windowTitle) {
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
                } else if pairTest {
                    pairBody
                        .onAppear { harness.boot(files: sendFiles) }
                        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                            harness.stop()
                        }
                } else {
                    ContentView()
                        .environmentObject(store)
                        .frame(minWidth: 820, minHeight: 520)
                        .onAppear {
                            store.start()
                            if demoTransfer {
                                store.playSendReceiveDemo()
                            } else if !sendFiles.isEmpty {
                                store.runSendReceiveTest(files: sendFiles)
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                            store.stop()
                        }
                }
            }
        }
        .defaultSize(width: pairTest ? 1180 : 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    @ViewBuilder
    private var pairBody: some View {
        if let sender = harness.sender, let receiver = harness.receiver {
            PairTestView(sender: sender, receiver: receiver)
                .frame(minWidth: 1100, minHeight: 560)
        } else if let error = harness.error {
            Text(error).padding(32)
        } else {
            Text("Starting sender and receiver…")
                .foregroundStyle(.secondary)
                .frame(minWidth: 1100, minHeight: 560)
        }
    }
}
