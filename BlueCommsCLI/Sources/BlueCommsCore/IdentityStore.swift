import CryptoKit
import Foundation
import SystemConfiguration

public func localComputerName() -> String {
    if let name = SCDynamicStoreCopyComputerName(nil, nil) as String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    let host = ProcessInfo.processInfo.hostName
        .replacingOccurrences(of: ".local", with: "")
        .replacingOccurrences(of: ".lan", with: "")
    return host.isEmpty ? "Mac" : host
}

public struct DeviceIdentity: Sendable {
    public let id: UUID
    public let displayName: String
    public let privateKey: Curve25519.KeyAgreement.PrivateKey

    public var publicKeyData: Data { privateKey.publicKey.rawRepresentation }
    public var shortID: String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }
    public var fingerprint: String { keyFingerprint(publicKeyData) }

    public var bonjourName: String {
        let suffix = " · \(shortID)"
        let budget = max(0, 63 - suffix.utf8.count)
        var base = displayName
        while base.utf8.count > budget && !base.isEmpty {
            base.removeLast()
        }
        return base + suffix
    }

    public init(id: UUID, displayName: String, privateKey: Curve25519.KeyAgreement.PrivateKey) {
        self.id = id
        self.displayName = displayName
        self.privateKey = privateKey
    }
}

public enum TOFUResult: Equatable, Sendable {
    case firstSeen
    case matched
}

public struct IdentityStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bluecomms", isDirectory: true)
    }

    public func loadOrCreate() throws -> DeviceIdentity {
        try ensureDirectory()
        let id = try loadOrCreateDeviceID()
        let privateKey = try loadOrCreatePrivateKey()
        let displayName = localComputerName()
        return DeviceIdentity(
            id: id,
            displayName: displayName.isEmpty ? "Unknown Mac" : displayName,
            privateKey: privateKey
        )
    }

    public func verifyOrRemember(peerID: UUID, publicKey: Data) throws -> TOFUResult {
        if let known = try knownPublicKey(for: peerID) {
            if known == publicKey { return .matched }
            throw CryptoError.tofuMismatch
        }
        try remember(peerID: peerID, publicKey: publicKey)
        return .firstSeen
    }

    public func knownPublicKey(for peerID: UUID) throws -> Data? {
        let peers = try loadKnownPeers()
        guard let encoded = peers[peerID.uuidString] else { return nil }
        return Data(base64Encoded: encoded)
    }

    public func remember(peerID: UUID, publicKey: Data) throws {
        var peers = try loadKnownPeers()
        peers[peerID.uuidString] = publicKey.base64EncodedString()
        try saveKnownPeers(peers)
    }

    private var deviceIDURL: URL { directory.appendingPathComponent("device-id") }
    private var identityURL: URL { directory.appendingPathComponent("identity") }
    private var knownPeersURL: URL { directory.appendingPathComponent("known-peers.json") }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func loadOrCreateDeviceID() throws -> UUID {
        if let raw = try? String(contentsOf: deviceIDURL, encoding: .utf8),
           let id = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return id
        }
        let id = UUID()
        try writeProtected(Data(id.uuidString.utf8), to: deviceIDURL)
        return id
    }

    private func loadOrCreatePrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let data = try? Data(contentsOf: identityURL),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try writeProtected(key.rawRepresentation, to: identityURL)
        return key
    }

    private func loadKnownPeers() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: knownPeersURL.path) else { return [:] }
        let data = try Data(contentsOf: knownPeersURL)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func saveKnownPeers(_ peers: [String: String]) throws {
        let data = try JSONEncoder().encode(peers)
        try writeProtected(data, to: knownPeersURL)
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
