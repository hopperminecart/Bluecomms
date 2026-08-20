import CryptoKit
import Foundation

/// Encrypted chat history next to the identity files.
public struct MessageArchive: Sendable {
    public let directory: URL
    private let key: SymmetricKey

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        self.key = try Self.loadOrCreateKey(in: directory)
    }

    public func load() throws -> ConversationSnapshot {
        let url = archiveURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ConversationSnapshot()
        }
        let blob = try Data(contentsOf: url)
        let plaintext = try decrypt(blob)
        return try JSONDecoder().decode(ConversationSnapshot.self, from: plaintext)
    }

    public func save(_ snapshot: ConversationSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        let blob = try encrypt(data)
        try blob.write(to: archiveURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
    }

    private var archiveURL: URL {
        directory.appendingPathComponent("conversations.bin")
    }

    private var keyURL: URL {
        directory.appendingPathComponent("archive.key")
    }

    private static func loadOrCreateKey(in directory: URL) throws -> SymmetricKey {
        let url = directory.appendingPathComponent("archive.key")
        if let data = try? Data(contentsOf: url), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return key
    }

    private func encrypt(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw ArchiveError.encryptFailed
        }
        return combined
    }

    private func decrypt(_ blob: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: blob)
        return try AES.GCM.open(box, using: key)
    }
}

public enum ArchiveError: Error, Equatable, Sendable {
    case encryptFailed
}
