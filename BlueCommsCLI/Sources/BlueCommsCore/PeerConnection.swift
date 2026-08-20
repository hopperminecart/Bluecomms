import CryptoKit
import Foundation
import Network

/// One TCP session: handshake, framed chat, chunked files.
/// `isComplete` on send must stay false or the first chat line FINs the stream.
final class PeerConnection: @unchecked Sendable {
    let id: UUID
    let connection: NWConnection

    var onStateChange: ((NWConnection.State) -> Void)?
    var onReadyForChat: ((UUID) -> Void)?
    var onMessageReceived: ((String) -> Void)?
    var onFileTransfer: ((FileTransferUpdate) -> Void)?
    var onHandshake: ((HandshakePayload) throws -> TOFUResult)?
    var onLog: ((String) -> Void)?

    private let queue: DispatchQueue
    private let identity: DeviceIdentity
    private let decoder = FrameDecoder()
    private var crypto: CryptoSession
    private var handshakeSent = false
    private var handshakeReceived = false
    private var receiving = false
    private var outboundQueue: [String] = []
    private var closed = false
    private var handshakeTimeoutWork: DispatchWorkItem?
    private var outgoing: [UUID: OutgoingTransfer] = [:]
    private var incoming: [UUID: IncomingTransfer] = [:]

    static let maxChatBytes = 65_507
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
                if !self.receiving {
                    self.receiving = true
                    self.receiveLoop()
                }
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

    func sendFile(at url: URL, id: UUID = UUID()) {
        guard !closed else { return }
        if isReadyForMessages {
            startOutgoingFile(url, id: id)
            return
        }
        onLog?("[FILE] Not ready; wait for the handshake.")
    }

    func cancel() {
        handshakeTimeoutWork?.cancel()
        closed = true
        outboundQueue.removeAll()
        failAllTransfers()
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] content, _, isComplete, error in
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
        guard let first = frame.first else {
            cancel()
            return
        }
        guard let type = WireType(rawValue: first) else {
            onLog?("[RECEIVE] Ignoring unknown frame type \(first).")
            return
        }
        let body = frame.dropFirst()
        switch type {
        case .handshake:
            try handleHandshake(Data(body))
        case .ciphertext:
            try handleCiphertext(Data(body))
        case .file:
            try handleFileBlob(Data(body))
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

    private func handleFileBlob(_ body: Data) throws {
        guard handshakeReceived else {
            onLog?("[FILE] File frame before handshake; dropping connection.")
            cancel()
            return
        }
        let plaintext = try crypto.open(body)
        let message = try FileMessage.decode(plaintext)
        handleFileMessage(message)
    }

    private func sendCiphertext(_ message: String) {
        var plaintext = Data(message.utf8)
        if plaintext.count > Self.maxChatBytes {
            onLog?("[SEND] Message truncated to \(Self.maxChatBytes) bytes.")
            plaintext = plaintext.prefix(Self.maxChatBytes)
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

    private struct OutgoingTransfer {
        let id: UUID
        let name: String
        let size: UInt64
        let url: URL
        let scoped: Bool
        var handle: FileHandle
        var offset: UInt64
        var inflight: Int
        var hasher: SHA256
        var accepted: Bool
    }

    private struct IncomingTransfer {
        let id: UUID
        let name: String
        let size: UInt64
        let partURL: URL
        let finalURL: URL
        var handle: FileHandle
        var received: UInt64
        var hasher: SHA256
    }

    private func startOutgoingFile(_ url: URL, id: UUID) {
        let accessed = url.startAccessingSecurityScopedResource()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true, let size = values?.fileSize, size > 0 else {
            if accessed { url.stopAccessingSecurityScopedResource() }
            onLog?("[FILE] Not a readable file.")
            return
        }
        guard UInt64(size) <= FileMessage.maxFileSize else {
            if accessed { url.stopAccessingSecurityScopedResource() }
            onLog?("[FILE] File is larger than the 8 GB cap.")
            return
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            let name = url.lastPathComponent
            outgoing[id] = OutgoingTransfer(
                id: id,
                name: name,
                size: UInt64(size),
                url: url,
                scoped: accessed,
                handle: handle,
                offset: 0,
                inflight: 0,
                hasher: SHA256(),
                accepted: false
            )
            try emitFile(.offer(id: id, size: UInt64(size), name: name))
            publishFile(id: id, name: name, size: UInt64(size), bytes: 0, outgoing: true, state: .transferring, url: url, error: nil)
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            onLog?("[FILE] Could not open \(url.lastPathComponent): \(error)")
        }
    }

    private func handleFileMessage(_ message: FileMessage) {
        switch message {
        case .offer(let id, let size, let name):
            acceptIncoming(id: id, size: size, name: name)
        case .accept(let id, let resumeFrom):
            guard var transfer = outgoing[id] else { return }
            transfer.accepted = true
            // Always send from byte 0. Resume would skip bytes the hasher still needs.
            if resumeFrom != 0 {
                onLog?("[FILE] Peer asked to resume; restarting from the beginning.")
            }
            outgoing[id] = transfer
            fillWindow(id)
        case .reject(let id):
            failOutgoing(id, "Peer declined the file")
        case .chunk(let id, let offset, let data):
            writeIncoming(id: id, offset: offset, data: data)
        case .ack(let id, let receivedUpTo):
            guard var transfer = outgoing[id] else { return }
            if receivedUpTo > transfer.offset {
                transfer.offset = receivedUpTo
            }
            transfer.inflight = max(0, transfer.inflight - 1)
            outgoing[id] = transfer
            publishFile(id: id, name: transfer.name, size: transfer.size, bytes: min(receivedUpTo, transfer.size), outgoing: true, state: .transferring, url: transfer.url, error: nil)
            fillWindow(id)
        case .complete(let id, let digest):
            finishIncoming(id: id, digest: digest)
        case .cancel(let id):
            if outgoing[id] != nil { failOutgoing(id, "Cancelled") }
            if incoming[id] != nil { failIncoming(id, "Cancelled") }
        }
    }

    private func acceptIncoming(id: UUID, size: UInt64, name: String) {
        if incoming[id] != nil { return }
        if size > FileMessage.maxFileSize {
            try? emitFile(.reject(id: id))
            return
        }
        let inbox = incomingInboxURL()
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let finalURL = uniqueDestination(directory: inbox, name: name)
            let partURL = inbox.appendingPathComponent(".\(id.uuidString).part")
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: partURL)
            incoming[id] = IncomingTransfer(
                id: id,
                name: name,
                size: size,
                partURL: partURL,
                finalURL: finalURL,
                handle: handle,
                received: 0,
                hasher: SHA256()
            )
            try emitFile(.accept(id: id, resumeFrom: 0))
            publishFile(id: id, name: name, size: size, bytes: 0, outgoing: false, state: .transferring, url: nil, error: nil)
        } catch {
            try? emitFile(.reject(id: id))
            onLog?("[FILE] Could not create inbox file: \(error)")
        }
    }

    private func writeIncoming(id: UUID, offset: UInt64, data: Data) {
        guard var transfer = incoming[id] else { return }
        guard offset == transfer.received else { return }
        do {
            try transfer.handle.write(contentsOf: data)
            transfer.hasher.update(data: data)
            transfer.received += UInt64(data.count)
            incoming[id] = transfer
            try emitFile(.ack(id: id, receivedUpTo: transfer.received))
            publishFile(id: id, name: transfer.name, size: transfer.size, bytes: transfer.received, outgoing: false, state: .transferring, url: nil, error: nil)
        } catch {
            failIncoming(id, "Write failed")
        }
    }

    private func finishIncoming(id: UUID, digest: Data) {
        guard let transfer = incoming.removeValue(forKey: id) else { return }
        try? transfer.handle.close()
        let actual = Data(transfer.hasher.finalize())
        guard actual == digest, transfer.received == transfer.size else {
            try? FileManager.default.removeItem(at: transfer.partURL)
            publishFile(id: id, name: transfer.name, size: transfer.size, bytes: transfer.received, outgoing: false, state: .failed, url: nil, error: "Checksum failed")
            return
        }
        do {
            if FileManager.default.fileExists(atPath: transfer.finalURL.path) {
                try FileManager.default.removeItem(at: transfer.finalURL)
            }
            try FileManager.default.moveItem(at: transfer.partURL, to: transfer.finalURL)
            publishFile(id: id, name: transfer.name, size: transfer.size, bytes: transfer.size, outgoing: false, state: .complete, url: transfer.finalURL, error: nil)
            onLog?("[FILE] Received \(transfer.name) → \(transfer.finalURL.path)")
        } catch {
            publishFile(id: id, name: transfer.name, size: transfer.size, bytes: transfer.received, outgoing: false, state: .failed, url: nil, error: "Could not save file")
        }
    }

    private func fillWindow(_ id: UUID) {
        guard !closed, var transfer = outgoing[id], transfer.accepted else { return }
        while transfer.inflight < FileMessage.windowChunks, transfer.offset < transfer.size {
            let remaining = transfer.size - transfer.offset
            let length = Int(min(UInt64(FileMessage.chunkSize), remaining))
            let data: Data
            do {
                guard let read = try transfer.handle.read(upToCount: length), read.count == length else {
                    failOutgoing(id, "Read failed")
                    return
                }
                data = read
            } catch {
                failOutgoing(id, "Read failed")
                return
            }
            transfer.hasher.update(data: data)
            do {
                try emitFile(.chunk(id: id, offset: transfer.offset, data: data))
            } catch {
                failOutgoing(id, "Send failed")
                return
            }
            transfer.offset += UInt64(data.count)
            transfer.inflight += 1
            outgoing[id] = transfer
        }
        if transfer.offset >= transfer.size, transfer.inflight == 0 {
            let digest = Data(transfer.hasher.finalize())
            try? emitFile(.complete(id: id, sha256: digest))
            try? transfer.handle.close()
            if transfer.scoped { transfer.url.stopAccessingSecurityScopedResource() }
            outgoing[id] = nil
            publishFile(id: id, name: transfer.name, size: transfer.size, bytes: transfer.size, outgoing: true, state: .complete, url: transfer.url, error: nil)
            onLog?("[FILE] Sent \(transfer.name)")
        }
    }

    private func failOutgoing(_ id: UUID, _ reason: String) {
        guard let transfer = outgoing.removeValue(forKey: id) else { return }
        try? transfer.handle.close()
        if transfer.scoped { transfer.url.stopAccessingSecurityScopedResource() }
        try? emitFile(.cancel(id: id))
        publishFile(id: id, name: transfer.name, size: transfer.size, bytes: transfer.offset, outgoing: true, state: .failed, url: transfer.url, error: reason)
        onLog?("[FILE] \(reason): \(transfer.name)")
    }

    private func failIncoming(_ id: UUID, _ reason: String) {
        guard let transfer = incoming.removeValue(forKey: id) else { return }
        try? transfer.handle.close()
        try? FileManager.default.removeItem(at: transfer.partURL)
        try? emitFile(.cancel(id: id))
        publishFile(id: id, name: transfer.name, size: transfer.size, bytes: transfer.received, outgoing: false, state: .failed, url: nil, error: reason)
    }

    private func failAllTransfers() {
        for id in Array(outgoing.keys) { failOutgoing(id, "Connection closed") }
        for id in Array(incoming.keys) { failIncoming(id, "Connection closed") }
    }

    private func emitFile(_ message: FileMessage) throws {
        let plaintext = try message.encoded()
        let sealed = try crypto.seal(plaintext)
        sendFrame(type: .file, body: sealed)
    }

    private func publishFile(
        id: UUID,
        name: String,
        size: UInt64,
        bytes: UInt64,
        outgoing: Bool,
        state: FileTransferState,
        url: URL?,
        error: String?
    ) {
        onFileTransfer?(
            FileTransferUpdate(
                transferID: id,
                name: name,
                size: size,
                bytes: bytes,
                isOutgoing: outgoing,
                state: state,
                localURL: url,
                error: error
            )
        )
    }
}
