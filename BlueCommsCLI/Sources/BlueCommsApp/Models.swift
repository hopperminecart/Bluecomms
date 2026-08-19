import Foundation

struct NearbyPeer: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let shortName: String
    var isOnline: Bool
}

struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let peerID: String
    let text: String
    let isLocal: Bool
    let sentAt: Date

    init(id: UUID = UUID(), peerID: String, text: String, isLocal: Bool, sentAt: Date = Date()) {
        self.id = id
        self.peerID = peerID
        self.text = text
        self.isLocal = isLocal
        self.sentAt = sentAt
    }
}

enum ConnectionPhase: Equatable, Sendable {
    case idle
    case connecting
    case ready
}
