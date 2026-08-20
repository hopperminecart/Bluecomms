//
//  Models.swift
//
//  Why this file exists:
//    SwiftUI needs Identifiable, Hashable types. The radio has DiscoveredPeer
//    (Bonjour only). The sidebar also needs last-seen and LIVE, so we keep a
//    separate NearbyPeer here (PR #4).
//

import Foundation

/// A nearby Mac from Bonjour, plus whether we have a live TCP session.
struct NearbyPeer: Identifiable, Hashable, Sendable {
    /// Device UUID string from the Bonjour TXT `id` key.
    let id: String
    let displayName: String
    /// First 8 hex chars of the id, shown under the name.
    let shortName: String
    /// Still in the current Bonjour browse results.
    var isOnline: Bool
    /// Last time they appeared or disappeared from Bonjour.
    var lastSeen: Date
    /// Handshake finished. Shows the LIVE badge.
    var isSessionOpen: Bool
}

/// Connect button state. ready = at least one handshake is up.
enum ConnectionPhase: Equatable, Sendable {
    case idle, connecting, ready
}
