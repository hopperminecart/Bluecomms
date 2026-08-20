import Foundation

/// A nearby Mac from Bonjour, plus whether we have a live TCP session.
struct NearbyPeer: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let shortName: String
    var isOnline: Bool
    var lastSeen: Date
    var isSessionOpen: Bool
}

enum ConnectionPhase: Equatable, Sendable {
    case idle, connecting, ready
}
