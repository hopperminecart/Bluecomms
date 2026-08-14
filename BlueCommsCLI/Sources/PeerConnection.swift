import Foundation
import Network

final class PeerConnection: @unchecked Sendable {
    let connection: NWConnection
    let id: UUID
    var onStateChange: ((NWConnection.State) -> Void)?
    var onMessageReceived: ((String) -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
        self.id = UUID()
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?(state)
            if state == .ready {
                self?.receiveMessage()
            }
        }
        connection.start(queue: .main)
    }

    func send(message: String) {
        let data = Data(message.utf8)
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("[SEND] Failed to send: \(error)")
            }
        }))
    }

    private func receiveMessage() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, context, isComplete, error in
            if let data = content, !data.isEmpty, let message = String(data: data, encoding: .utf8) {
                self?.onMessageReceived?(message)
            }
            if let error = error {
                print("[RECEIVE] Error: \(error)")
                self?.connection.cancel()
                return
            }
            if isComplete {
                self?.connection.cancel()
                return
            }
            self?.receiveMessage()
        }
    }
    
    func cancel() {
        connection.cancel()
    }
}
