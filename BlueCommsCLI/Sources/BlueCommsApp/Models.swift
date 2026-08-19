import Foundation

struct NearbyPeer: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let shortName: String
    var isOnline: Bool
    var lastSeen: Date
    var isSessionOpen: Bool
}

enum ConnectionPhase: Equatable, Sendable {
    case idle
    case connecting
    case ready
}
