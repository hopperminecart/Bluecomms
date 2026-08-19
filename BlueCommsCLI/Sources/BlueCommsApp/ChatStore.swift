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

    init(demo: Bool) throws {
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

        let manager = try NetworkManager()
        self.manager = manager
        localName = manager.deviceName
        shortID = manager.shortID
        fingerprint = manager.fingerprint
        statusLine = "Starting local radio…"
        archive = try MessageArchive(directory: IdentityStore.defaultDirectory)
        if let saved = try? archive?.load() {
            conversations = saved.conversations
        }
        bind(manager)
        manager.start()
    }

    func select(peerID: String) {
        selectedPeerID = peerID
    }

    func connectToSelection() {
        guard let peer = selectedPeer else { return }
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
                let key = peerID.uuidString
                self?.connectedIDs.insert(key)
                self?.markSession(peerID: key, open: true)
                self?.selectedPeerID = key
                self?.phase = .ready
                let name = self?.peers.first(where: { $0.id == key })?.displayName ?? "peer"
                self?.statusLine = "Secure session with \(name)"
                self?.flushOutbound(for: key)
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
            if !isDemo {
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
        for peer in discovered {
            if let index = peers.firstIndex(where: { $0.id == peer.id }) {
                peers[index].isOnline = true
                peers[index].lastSeen = now
            } else {
                peers.append(
                    NearbyPeer(
                        id: peer.id,
                        displayName: peer.displayName,
                        shortName: peer.shortName,
                        isOnline: true,
                        lastSeen: now,
                        isSessionOpen: connectedIDs.contains(peer.id)
                    )
                )
            }
        }
        for index in peers.indices where !onlineIDs.contains(peers[index].id) {
            if peers[index].isOnline {
                peers[index].isOnline = false
                peers[index].lastSeen = now
            }
        }
        if !peers.isEmpty, statusLine.contains("Starting") {
            statusLine = "Nearby peers updated"
        }
    }

    private func markSession(peerID: String, open: Bool) {
        if let index = peers.firstIndex(where: { $0.id == peerID }) {
            peers[index].isSessionOpen = open
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
    }
}
