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
    private var connectedPeerID: String?

    var selectedPeer: NearbyPeer? {
        peers.first(where: { $0.id == selectedPeerID })
    }

    var selectedMessages: [ChatMessage] {
        guard let selectedPeerID else { return [] }
        return conversations[selectedPeerID] ?? []
    }

    var isConnectedToSelection: Bool {
        phase == .ready && connectedPeerID == selectedPeerID
    }

    init(demo: Bool) throws {
        isDemo = demo
        if demo {
            localName = "Rishi’s MacBook Air"
            shortID = "08FE967E"
            fingerprint = "CD81-C9EF-1522"
            statusLine = "Demo mode — nearby radios are simulated"
            installDemoData()
            return
        }

        let manager = try NetworkManager()
        self.manager = manager
        localName = manager.deviceName
        shortID = manager.shortID
        fingerprint = manager.fingerprint
        statusLine = "Starting local radio…"
        bind(manager)
        manager.start()
    }

    func select(peerID: String) {
        selectedPeerID = peerID
    }

    func connectToSelection() {
        guard let peer = selectedPeer else { return }
        if isDemo {
            connectedPeerID = peer.id
            phase = .ready
            statusLine = "Secure session with \(peer.displayName)"
            return
        }
        phase = .connecting
        statusLine = "Connecting to \(peer.displayName)…"
        manager?.connectToPeer(id: peer.id)
    }

    func disconnect() {
        if isDemo {
            connectedPeerID = nil
            phase = .idle
            statusLine = "Demo mode — nearby radios are simulated"
            return
        }
        manager?.disconnect()
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let peerID = selectedPeerID else { return }
        draft = ""
        append(ChatMessage(peerID: peerID, text: text, isLocal: true))
        if isDemo {
            return
        }
        if isConnectedToSelection {
            manager?.send(message: text)
        } else {
            statusLine = "Not connected. Click Connect to deliver this."
        }
    }

    func stop() {
        manager?.stop()
    }

    private func bind(_ manager: NetworkManager) {
        manager.onPeersUpdated = { [weak self] discovered in
            Task { @MainActor in
                self?.peers = discovered.map {
                    NearbyPeer(id: $0.id, displayName: $0.displayName, shortName: $0.shortName, isOnline: true)
                }
                if self?.peers.isEmpty == false, self?.statusLine.contains("Starting") == true {
                    self?.statusLine = "Nearby peers updated"
                }
            }
        }
        manager.onSecureSession = { [weak self] peerID in
            Task { @MainActor in
                self?.connectedPeerID = peerID.uuidString
                self?.selectedPeerID = peerID.uuidString
                self?.phase = .ready
                let name = self?.peers.first(where: { $0.id == peerID.uuidString })?.displayName ?? "peer"
                self?.statusLine = "Secure session with \(name)"
            }
        }
        manager.onDisconnected = { [weak self] in
            Task { @MainActor in
                self?.connectedPeerID = nil
                self?.phase = .idle
                self?.statusLine = "Disconnected"
            }
        }
        manager.onMessageReceived = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                let peerID = self.connectedPeerID ?? self.selectedPeerID ?? "unknown"
                self.append(ChatMessage(peerID: peerID, text: text, isLocal: false))
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

    private func installDemoData() {
        let harsh = NearbyPeer(
            id: "E5F6A1B2-1111-2222-3333-444444444444",
            displayName: "Harsh’s MacBook Air",
            shortName: "E5F6A1B2",
            isOnline: true
        )
        let studio = NearbyPeer(
            id: "91AA20CC-AAAA-BBBB-CCCC-DDDDDDDDDDDD",
            displayName: "Studio Mac mini",
            shortName: "91AA20CC",
            isOnline: true
        )
        peers = [harsh, studio]
        selectedPeerID = harsh.id
        connectedPeerID = harsh.id
        phase = .ready
        conversations[harsh.id] = [
            ChatMessage(peerID: harsh.id, text: "You on AWDL?", isLocal: false, sentAt: Date().addingTimeInterval(-420)),
            ChatMessage(peerID: harsh.id, text: "Yeah. Wi-Fi on, no router. Fingerprints matched.", isLocal: true, sentAt: Date().addingTimeInterval(-400)),
            ChatMessage(peerID: harsh.id, text: "First send used to kill the socket. This one is still up.", isLocal: false, sentAt: Date().addingTimeInterval(-360)),
            ChatMessage(peerID: harsh.id, text: "Sending a real message from the Mac app now.", isLocal: true, sentAt: Date().addingTimeInterval(-20)),
        ]
        conversations[studio.id] = [
            ChatMessage(peerID: studio.id, text: "Last seen downstairs.", isLocal: false, sentAt: Date().addingTimeInterval(-3600)),
        ]
    }
}
