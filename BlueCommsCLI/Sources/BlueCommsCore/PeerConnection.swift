import Foundation
import Network

final class PeerConnection: @unchecked Sendable {
    let id: UUID
    let connection: NWConnection

    var onStateChange: ((NWConnection.State) -> Void)?
    var onReadyForChat: ((UUID) -> Void)?
    var onMessageReceived: ((String) -> Void)?
    var onHandshake: ((HandshakePayload) throws -> TOFUResult)?
    var onLog: ((String) -> Void)?

    private let queue: DispatchQueue
    private let identity: DeviceIdentity
    private let decoder = FrameDecoder()
    private var crypto: CryptoSession
    private var handshakeSent = false
    private var handshakeReceived = false
    private var outboundQueue: [String] = []
    private var closed = false
    private var handshakeTimeoutWork: DispatchWorkItem?

    static let maxPlaintextBytes = FrameCodec.maxPayloadSize - 1 - 12 - 16
    private static let handshakeTimeout: TimeInterval = 10
    private static let maxQueuedMessages = 32

    var isReadyForMessages: Bool {
        handshakeSent && handshakeReceived && !closed
    }

    init(connection: NWConnection, identity: DeviceIdentity, queue: DispatchQueue) {
        self.id = UUID()
        self.connection = connection
        self.identity = identity
        self.queue = queue
        self.crypto = CryptoSession(localPrivateKey: identity.privateKey)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.onStateChange?(state)
            if state == .ready {
                self.sendHandshake()
                self.receiveLoop()
            }
            if Self.isTerminal(state) {
                self.closed = true
                self.handshakeTimeoutWork?.cancel()
            }
        }
        scheduleHandshakeTimeout()
        connection.start(queue: queue)
    }

    func send(message: String) {
        guard !closed else { return }
        if isReadyForMessages {
            sendCiphertext(message)
            return
        }
        guard outboundQueue.count < Self.maxQueuedMessages else {
            onLog?("[SEND] Dropped message; handshake still in progress and queue is full.")
            return
        }
        outboundQueue.append(message)
    }

    func cancel() {
        handshakeTimeoutWork?.cancel()
        closed = true
        outboundQueue.removeAll()
        connection.cancel()
    }

    private static func isTerminal(_ state: NWConnection.State) -> Bool {
        switch state {
        case .failed, .cancelled: return true
        default: return false
        }
    }

    private func sendHandshake() {
        guard !handshakeSent, !closed else { return }
        let payload = HandshakePayload(peerID: identity.id, publicKey: identity.publicKeyData)
        sendFrame(type: .handshake, body: payload.encoded())
        handshakeSent = true
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] content, _, isComplete, error in
            guard let self, !self.closed else { return }

            if let content, !content.isEmpty {
                do {
                    let frames = try self.decoder.append(content)
                    for frame in frames {
                        try self.handleFrame(frame)
                    }
                } catch CryptoError.tofuMismatch {
                    self.onLog?("[SECURITY] Peer identity key changed. Refusing to connect.")
                    self.cancel()
                    return
                } catch {
                    self.onLog?("[RECEIVE] Protocol error: \(error)")
                    self.cancel()
                    return
                }
            }

            if let error {
                self.onLog?("[RECEIVE] Error: \(error)")
                self.cancel()
                return
            }

            if isComplete {
                self.cancel()
                return
            }

            self.receiveLoop()
        }
    }

    private func handleFrame(_ frame: Data) throws {
        guard let first = frame.first, let type = WireType(rawValue: first) else {
            onLog?("[RECEIVE] Unknown frame type.")
            cancel()
            return
        }
        let body = frame.dropFirst()
        switch type {
        case .handshake:
            try handleHandshake(Data(body))
        case .ciphertext:
            try handleCiphertext(Data(body))
        }
    }

    private func handleHandshake(_ body: Data) throws {
        guard !handshakeReceived else {
            onLog?("[CONNECTION] Unexpected extra handshake.")
            return
        }
        let payload = try HandshakePayload.decode(body)
        let result = try onHandshake?(payload) ?? .firstSeen
        try crypto.establish(peerPublicKey: payload.publicKey)
        handshakeReceived = true
        handshakeTimeoutWork?.cancel()

        let peerFP = keyFingerprint(payload.publicKey)
        switch result {
        case .firstSeen:
            onLog?("[SECURITY] First time seeing this peer.")
            onLog?("[SECURITY] Your fingerprint: \(identity.fingerprint)")
            onLog?("[SECURITY] Peer fingerprint: \(peerFP)")
            onLog?("[SECURITY] Compare these with your friend. They should match in reverse.")
        case .matched:
            onLog?("[SECURITY] Known peer. Fingerprint \(peerFP)")
        }

        flushOutboundQueue()
        onReadyForChat?(payload.peerID)
    }

    private func handleCiphertext(_ body: Data) throws {
        guard handshakeReceived else {
            onLog?("[RECEIVE] Ciphertext before handshake; dropping connection.")
            cancel()
            return
        }
        let plaintext = try crypto.open(body)
        guard let message = String(data: plaintext, encoding: .utf8) else {
            onLog?("[RECEIVE] Dropped a message that was not valid UTF-8.")
            return
        }
        onMessageReceived?(message)
    }

    private func sendCiphertext(_ message: String) {
        var plaintext = Data(message.utf8)
        if plaintext.count > Self.maxPlaintextBytes {
            onLog?("[SEND] Message truncated to \(Self.maxPlaintextBytes) bytes.")
            plaintext = plaintext.prefix(Self.maxPlaintextBytes)
        }
        do {
            let sealed = try crypto.seal(plaintext)
            sendFrame(type: .ciphertext, body: sealed)
            onLog?("[SEND] \(plaintext.count) bytes")
        } catch {
            onLog?("[SEND] Encrypt failed: \(error)")
        }
    }

    private func flushOutboundQueue() {
        let pending = outboundQueue
        outboundQueue.removeAll()
        for message in pending {
            sendCiphertext(message)
        }
    }

    private func sendFrame(type: WireType, body: Data) {
        var payload = Data([type.rawValue])
        payload.append(body)
        do {
            let framed = try FrameCodec.encode(payload)
            connection.send(content: framed, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.onLog?("[SEND] Failed to send: \(error)")
                }
            })
        } catch {
            onLog?("[SEND] Framing error: \(error)")
        }
    }

    private func scheduleHandshakeTimeout() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.handshakeReceived, !self.closed else { return }
            self.onLog?("[CONNECTION] Handshake timed out.")
            self.cancel()
        }
        handshakeTimeoutWork = work
        queue.asyncAfter(deadline: .now() + Self.handshakeTimeout, execute: work)
    }
}
