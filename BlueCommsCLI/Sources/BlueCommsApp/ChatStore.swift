import BlueCommsCore
import Combine
import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var peers: [NearbyPeer] = []
    @Published var conversations: [String: [ChatMessage]] = [:]
    @Published var selectedPeerID: String?
    @Published var draft: String = ""
    @Published var phase: ConnectionPhase = .idle
    @Published var statusLine: String
    @Published var logs: [String] = []

    let localName: String
    let shortID: String
    let fingerprint: String
    let isDemo: Bool

    private var manager: NetworkManager?
    private var connectedIDs: Set<String> = []
    private var archive: MessageArchive?
    private var didStart = false

    var selectedPeer: NearbyPeer? {
        peers.first(where: { $0.id == selectedPeerID })
    }

    var selectedMessages: [ChatMessage] {
        guard let selectedPeerID else { return [] }
        return conversations[selectedPeerID] ?? []
    }

    var isConnectedToSelection: Bool {
        guard let selectedPeerID else { return false }
        return connectedIDs.contains(selectedPeerID)
    }

    static var placeholder: ChatStore {
        try! ChatStore(demo: true)
    }

    init(demo: Bool, dataDirectory: URL? = nil) throws {
        isDemo = demo
        if demo {
            localName = "Rishi’s MacBook Air"
            shortID = "08FE967E"
            fingerprint = "CD81-C9EF-1522"
            statusLine = "Demo mode — nearby radios are simulated"
            archive = try? MessageArchive(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("bluecomms-demo-archive", isDirectory: true))
            if let saved = try? archive?.load(), !saved.conversations.isEmpty {
                conversations = saved.conversations
            }
            installDemoData()
            persist()
            return
        }

        let directory = dataDirectory ?? IdentityStore.defaultDirectory
        let manager = try NetworkManager(store: IdentityStore(directory: directory))
        self.manager = manager
        localName = manager.deviceName
        shortID = manager.shortID
        fingerprint = manager.fingerprint
        statusLine = "Starting local radio…"
        archive = try MessageArchive(directory: directory)
        if let saved = try? archive?.load() {
            conversations = saved.conversations
        }
        bind(manager)
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        manager?.start()
    }

    func select(peerID: String) {
        selectedPeerID = peerID
    }

    func connectToSelection() {
        guard let peer = selectedPeer else { return }
        guard peer.isOnline else {
            statusLine = "That peer is not nearby. The message will stay queued."
            return
        }
        if isDemo {
            connectedIDs.insert(peer.id)
            markSession(peerID: peer.id, open: true)
            phase = connectedIDs.isEmpty ? .idle : .ready
            statusLine = "Secure session with \(peer.displayName)"
            flushOutbound(for: peer.id)
            return
        }
        phase = .connecting
        statusLine = "Connecting to \(peer.displayName)…"
        manager?.connectToPeer(id: peer.id)
    }

    func disconnect() {
        if isDemo {
            if let id = selectedPeerID {
                connectedIDs.remove(id)
                markSession(peerID: id, open: false)
            }
            phase = connectedIDs.isEmpty ? .idle : .ready
            statusLine = "Disconnected this peer. Other sessions stay up."
            return
        }
        if let id = selectedPeerID {
            manager?.disconnect(from: id)
        } else {
            manager?.disconnect()
        }
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let peerID = selectedPeerID else { return }
        draft = ""
        let deliverNow = isConnectedToSelection
        append(ChatMessage(
            peerID: peerID,
            text: text,
            isLocal: true,
            delivery: deliverNow ? .sent : .queued
        ))
        if deliverNow {
            if !isDemo {
                manager?.send(message: text, to: peerID)
            }
        } else {
            statusLine = "Queued. It will send when this peer is back."
        }
        persist()
    }

    func sendFile(url: URL) {
        guard let peerID = selectedPeerID else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let name = url.lastPathComponent
        let transferID = UUID()
        let deliverNow = isConnectedToSelection
        append(ChatMessage(
            peerID: peerID,
            text: name,
            isLocal: true,
            delivery: deliverNow ? .sent : .queued,
            kind: .file,
            fileName: name,
            fileSize: size,
            filePath: url.path,
            transferID: transferID,
            progress: 0,
            fileState: deliverNow ? .transferring : .queued
        ))
        if deliverNow, !isDemo {
            manager?.send(file: url, to: peerID, id: transferID)
            statusLine = "Sending \(name)…"
        } else if isDemo {
            applyFileUpdate(
                peerID: UUID(uuidString: peerID) ?? UUID(),
                update: FileTransferUpdate(
                    transferID: transferID,
                    name: name,
                    size: size,
                    bytes: size,
                    isOutgoing: true,
                    state: .complete,
                    localURL: url,
                    error: nil
                )
            )
        } else {
            statusLine = "File queued. Connect to send \(name)."
        }
        persist()
    }

    func playSendReceiveDemo() {
        Task { @MainActor in
            let harshID = selectedPeerID ?? peers.first?.id ?? "demo"
            select(peerID: harshID)
            let shotID = UUID()
            append(ChatMessage(
                peerID: harshID,
                text: "screenshot.png",
                isLocal: true,
                kind: .file,
                fileName: "screenshot.png",
                fileSize: 2_400_000,
                transferID: shotID,
                progress: 0,
                fileState: .transferring
            ))
            statusLine = "Sending screenshot.png…"
            for step in 1...20 {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if let index = conversations[harshID]?.firstIndex(where: { $0.transferID == shotID }) {
                    conversations[harshID]?[index].progress = Double(step) / 20
                    if step == 20 {
                        conversations[harshID]?[index].fileState = .complete
                    }
                }
            }
            statusLine = "Screenshot delivered. Receiving clip.mp4…"
            let clipID = UUID()
            append(ChatMessage(
                peerID: harshID,
                text: "clip.mp4",
                isLocal: false,
                kind: .file,
                fileName: "clip.mp4",
                fileSize: 540 * 1024 * 1024,
                transferID: clipID,
                progress: 0,
                fileState: .transferring
            ))
            for step in 1...20 {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if let index = conversations[harshID]?.firstIndex(where: { $0.transferID == clipID }) {
                    conversations[harshID]?[index].progress = Double(step) / 20
                    if step == 20 {
                        conversations[harshID]?[index].fileState = .complete
                    }
                }
            }
            statusLine = "Received clip.mp4"
        }
    }

    func runSendReceiveTest(files: [URL]) {
        Task { @MainActor in
            statusLine = "Waiting for a nearby peer…"
            for _ in 0..<40 {
                if !peers.isEmpty { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard let peer = peers.first else {
                statusLine = "No peer appeared for the send/receive test."
                return
            }
            select(peerID: peer.id)
            connectToSelection()
            for _ in 0..<40 {
                if isConnectedToSelection { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard isConnectedToSelection else {
                statusLine = "Could not open a session for the send/receive test."
                return
            }
            for file in files {
                sendFile(url: file)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    func sendScreenshot() {
        guard let url = ScreenGrab.savePNG() else {
            statusLine = "Could not capture the screen. Grant Screen Recording in System Settings if asked."
            return
        }
        sendFile(url: url)
    }

    func stop() {
        manager?.stop()
    }

    private func bind(_ manager: NetworkManager) {
        manager.onPeersUpdated = { [weak self] discovered in
            Task { @MainActor in
                self?.mergePresence(discovered)
            }
        }
        manager.onSecureSession = { [weak self] peerID in
            Task { @MainActor in
                guard let self else { return }
                let key = peerID.uuidString
                self.ensurePeer(id: key)
                self.connectedIDs.insert(key)
                self.markSession(peerID: key, open: true)
                self.selectedPeerID = key
                self.phase = .ready
                let name = self.peers.first(where: { $0.id == key })?.displayName ?? "peer"
                self.statusLine = "Secure session with \(name)"
                self.flushOutbound(for: key)
            }
        }
        manager.onPeerDisconnected = { [weak self] peerID in
            Task { @MainActor in
                let key = peerID.uuidString
                self?.connectedIDs.remove(key)
                self?.markSession(peerID: key, open: false)
                self?.phase = self?.connectedIDs.isEmpty == true ? .idle : .ready
                self?.statusLine = "Disconnected \(key.prefix(8))"
            }
        }
        manager.onMessageFromPeer = { [weak self] peerID, text in
            Task { @MainActor in
                guard let self else { return }
                self.append(ChatMessage(peerID: peerID.uuidString, text: text, isLocal: false))
                self.persist()
            }
        }
        manager.onFileTransfer = { [weak self] peerID, update in
            Task { @MainActor in
                self?.applyFileUpdate(peerID: peerID, update: update)
            }
        }
        manager.onLog = { [weak self] line in
            Task { @MainActor in
                self?.logs.append(line)
                if self?.phase != .ready {
                    self?.statusLine = line
                }
            }
        }
    }

    private func append(_ message: ChatMessage) {
        conversations[message.peerID, default: []].append(message)
    }

    private func applyFileUpdate(peerID: UUID, update: FileTransferUpdate) {
        let key = peerID.uuidString
        if let index = conversations[key]?.firstIndex(where: { $0.transferID == update.transferID }) {
            conversations[key]?[index].progress = update.progress
            conversations[key]?[index].fileState = update.state
            if let path = update.localURL?.path {
                conversations[key]?[index].filePath = path
            }
            if update.state == .complete {
                conversations[key]?[index].delivery = .sent
                persist()
            }
            if update.state == .failed || update.state == .cancelled {
                persist()
                statusLine = update.error ?? "File transfer failed"
            }
            return
        }
        if !update.isOutgoing {
            append(ChatMessage(
                peerID: key,
                text: update.name,
                isLocal: false,
                kind: .file,
                fileName: update.name,
                fileSize: update.size,
                filePath: update.localURL?.path,
                transferID: update.transferID,
                progress: update.progress,
                fileState: update.state
            ))
            if update.state == .complete { persist() }
        }
    }

    private func persist() {
        let snapshot = ConversationSnapshot(
            conversations: conversations,
            outboundIDs: conversations.values.flatMap { $0 }.filter { $0.delivery == .queued }.map(\.id)
        )
        try? archive?.save(snapshot)
    }

    private func flushOutbound(for peerID: String) {
        guard var thread = conversations[peerID] else { return }
        var sentAny = false
        for index in thread.indices where thread[index].delivery == .queued && thread[index].isLocal {
            if thread[index].kind == .file {
                if !isDemo, let path = thread[index].filePath {
                    manager?.send(
                        file: URL(fileURLWithPath: path),
                        to: peerID,
                        id: thread[index].transferID ?? UUID()
                    )
                }
                thread[index].fileState = .transferring
            } else if !isDemo {
                manager?.send(message: thread[index].text, to: peerID)
            }
            thread[index].delivery = .sent
            sentAny = true
        }
        conversations[peerID] = thread
        if sentAny {
            statusLine = "Delivered queued messages to this peer."
        }
        persist()
    }

    private func mergePresence(_ discovered: [DiscoveredPeer]) {
        let onlineIDs = Set(discovered.map(\.id))
        let now = Date()
        var next = peers
        var changed = false
        for peer in discovered {
            if let index = next.firstIndex(where: { $0.id == peer.id }) {
                if !next[index].isOnline {
                    next[index].isOnline = true
                    changed = true
                }
            } else {
                next.append(
                    NearbyPeer(
                        id: peer.id,
                        displayName: peer.displayName,
                        shortName: peer.shortName,
                        isOnline: true,
                        lastSeen: now,
                        isSessionOpen: connectedIDs.contains(peer.id)
                    )
                )
                changed = true
            }
        }
        for index in next.indices where !onlineIDs.contains(next[index].id) {
            if next[index].isOnline {
                next[index].isOnline = false
                next[index].lastSeen = now
                changed = true
            }
        }
        if changed {
            peers = next
        }
        if !next.isEmpty, statusLine.contains("Starting") {
            statusLine = "Nearby peers updated"
        }
    }

    private func markSession(peerID: String, open: Bool) {
        if let index = peers.firstIndex(where: { $0.id == peerID }) {
            peers[index].isSessionOpen = open
        }
    }

    private func ensurePeer(id: String) {
        guard peers.contains(where: { $0.id == id }) else {
            let short = String(id.replacingOccurrences(of: "-", with: "").prefix(8))
            peers.append(
                NearbyPeer(
                    id: id,
                    displayName: "Peer \(short)",
                    shortName: short,
                    isOnline: true,
                    lastSeen: Date(),
                    isSessionOpen: true
                )
            )
            return
        }
    }

    private func installDemoData() {
        let harsh = NearbyPeer(
            id: "E5F6A1B2-1111-2222-3333-444444444444",
            displayName: "Harsh’s MacBook Air",
            shortName: "E5F6A1B2",
            isOnline: true,
            lastSeen: Date(),
            isSessionOpen: true
        )
        let studio = NearbyPeer(
            id: "91AA20CC-AAAA-BBBB-CCCC-DDDDDDDDDDDD",
            displayName: "Studio Mac mini",
            shortName: "91AA20CC",
            isOnline: false,
            lastSeen: Date().addingTimeInterval(-12 * 60),
            isSessionOpen: false
        )
        peers = [harsh, studio]
        selectedPeerID = harsh.id
        connectedIDs = [harsh.id]
        phase = .ready
        if conversations[harsh.id] == nil {
            conversations[harsh.id] = [
                ChatMessage(peerID: harsh.id, text: "You on AWDL?", isLocal: false, sentAt: Date().addingTimeInterval(-420)),
                ChatMessage(peerID: harsh.id, text: "Yeah. Wi-Fi on, no router. Fingerprints matched.", isLocal: true, sentAt: Date().addingTimeInterval(-400)),
                ChatMessage(peerID: harsh.id, text: "First send used to kill the socket. This one is still up.", isLocal: false, sentAt: Date().addingTimeInterval(-360)),
                ChatMessage(peerID: harsh.id, text: "Sending a real message from the Mac app now.", isLocal: true, sentAt: Date().addingTimeInterval(-20)),
            ]
        }
        if conversations[studio.id] == nil {
            conversations[studio.id] = [
                ChatMessage(peerID: studio.id, text: "Last seen downstairs.", isLocal: false, sentAt: Date().addingTimeInterval(-3600)),
                ChatMessage(
                    peerID: studio.id,
                    text: "Ping me when you are back upstairs.",
                    isLocal: true,
                    sentAt: Date().addingTimeInterval(-90),
                    delivery: .queued
                ),
            ]
        }
        if conversations[harsh.id]?.contains(where: { $0.kind == .file }) != true {
            conversations[harsh.id, default: []].append(
                ChatMessage(
                    peerID: harsh.id,
                    text: "clip.mov",
                    isLocal: true,
                    sentAt: Date().addingTimeInterval(-8),
                    kind: .file,
                    fileName: "clip.mov",
                    fileSize: 540 * 1024 * 1024,
                    transferID: UUID(),
                    progress: 0.62,
                    fileState: .transferring
                )
            )
        }
    }
}
