import Foundation

@MainActor
final class PairHarness: ObservableObject {
    @Published var sender: ChatStore?
    @Published var receiver: ChatStore?
    @Published var error: String?

    func boot(files: [URL]) {
        guard sender == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.bootNow(files: files)
        }
    }

    private func bootNow(files: [URL]) {
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("bluecomms-pair-test", isDirectory: true)
            let senderStore = try ChatStore(demo: false, dataDirectory: root.appendingPathComponent("sender"))
            let receiverStore = try ChatStore(demo: false, dataDirectory: root.appendingPathComponent("receiver"))
            senderStore.start()
            receiverStore.start()
            sender = senderStore
            receiver = receiverStore
            if !files.isEmpty {
                senderStore.runSendReceiveTest(files: files)
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    func stop() {
        sender?.stop()
        receiver?.stop()
    }
}
