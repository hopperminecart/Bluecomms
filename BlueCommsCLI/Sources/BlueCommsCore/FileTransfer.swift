//
//  FileTransfer.swift
//
//  Why this file exists:
//    Chat frames are tiny. Photos/video/files need a streaming protocol so
//    we never load a 500 MB–GB file into RAM (PR #5).
//
//  Wire (each FileMessage is then AES-GCM sealed as WireType.file):
//    offer → accept → 256 KB chunks → ack → complete(SHA-256)
//
//  Window is 8 chunks in flight. Cap 8 GB. Inbox: ~/Downloads/BlueComms.
//  Same AWDL radio as chat — stay nearby until the bar hits 100%.
//
//  UInt16 name length is encoded as [high, low] of the original value.
//  Do not write `value.bigEndian` then shift — that swapped bytes and
//  made every offer fail to decode.
//

import CryptoKit
import Foundation

public enum FileTransferState: String, Codable, Sendable {
    case queued
    case transferring
    case complete
    case failed
    case cancelled
}

/// Progress event ChatStore turns into a file card. Public so the UI can construct tests.
public struct FileTransferUpdate: Sendable {
    public let transferID: UUID
    public let name: String
    public let size: UInt64
    public let bytes: UInt64
    public let isOutgoing: Bool
    public let state: FileTransferState
    public let localURL: URL?
    public let error: String?

    public init(
        transferID: UUID,
        name: String,
        size: UInt64,
        bytes: UInt64,
        isOutgoing: Bool,
        state: FileTransferState,
        localURL: URL?,
        error: String?
    ) {
        self.transferID = transferID
        self.name = name
        self.size = size
        self.bytes = bytes
        self.isOutgoing = isOutgoing
        self.state = state
        self.localURL = localURL
        self.error = error
    }

    public var progress: Double {
        guard size > 0 else { return state == .complete ? 1 : 0 }
        return min(1, Double(bytes) / Double(size))
    }
}

public enum FileOpcode: UInt8 {
    case offer = 1
    case accept = 2
    case reject = 3
    case chunk = 4
    case ack = 5
    case complete = 6
    case cancel = 7
}

/// One control or data message inside a file frame.
public enum FileMessage: Equatable {
    public static let chunkSize = 256 * 1024
    public static let windowChunks = 8
    public static let maxFileSize: UInt64 = 8 * 1024 * 1024 * 1024
    public static let maxNameBytes = 255

    case offer(id: UUID, size: UInt64, name: String)
    case accept(id: UUID, resumeFrom: UInt64)
    case reject(id: UUID)
    case chunk(id: UUID, offset: UInt64, data: Data)
    case ack(id: UUID, receivedUpTo: UInt64)
    case complete(id: UUID, sha256: Data)
    case cancel(id: UUID)

    public func encoded() throws -> Data {
        switch self {
        case .offer(let id, let size, let name):
            var payload = Data([FileOpcode.offer.rawValue])
            payload.append(contentsOf: uuidBytes(id))
            payload.append(contentsOf: uInt64Bytes(size))
            let nameData = Data(name.utf8.prefix(Self.maxNameBytes))
            payload.append(contentsOf: uInt16Bytes(UInt16(nameData.count)))
            payload.append(nameData)
            return payload
        case .accept(let id, let resumeFrom):
            var payload = Data([FileOpcode.accept.rawValue])
            payload.append(contentsOf: uuidBytes(id))
            payload.append(contentsOf: uInt64Bytes(resumeFrom))
            return payload
        case .reject(let id):
            return Data([FileOpcode.reject.rawValue]) + uuidBytes(id)
        case .chunk(let id, let offset, let data):
            var payload = Data([FileOpcode.chunk.rawValue])
            payload.append(contentsOf: uuidBytes(id))
            payload.append(contentsOf: uInt64Bytes(offset))
            payload.append(data)
            return payload
        case .ack(let id, let receivedUpTo):
            var payload = Data([FileOpcode.ack.rawValue])
            payload.append(contentsOf: uuidBytes(id))
            payload.append(contentsOf: uInt64Bytes(receivedUpTo))
            return payload
        case .complete(let id, let digest):
            guard digest.count == 32 else { throw FileTransferError.badMessage }
            var payload = Data([FileOpcode.complete.rawValue])
            payload.append(contentsOf: uuidBytes(id))
            payload.append(digest)
            return payload
        case .cancel(let id):
            return Data([FileOpcode.cancel.rawValue]) + uuidBytes(id)
        }
    }

    public static func decode(_ data: Data) throws -> FileMessage {
        guard let raw = data.first, let opcode = FileOpcode(rawValue: raw) else {
            throw FileTransferError.badMessage
        }
        var rest = data.dropFirst()
        switch opcode {
        case .offer:
            let id = try takeUUID(&rest)
            let size = try takeUInt64(&rest)
            let nameLen = Int(try takeUInt16(&rest))
            guard rest.count >= nameLen, size <= maxFileSize else { throw FileTransferError.badMessage }
            let name = String(decoding: rest.prefix(nameLen), as: UTF8.self)
            return .offer(id: id, size: size, name: sanitizeFileName(name))
        case .accept:
            let id = try takeUUID(&rest)
            let resume = try takeUInt64(&rest)
            return .accept(id: id, resumeFrom: resume)
        case .reject:
            return .reject(id: try takeUUID(&rest))
        case .chunk:
            let id = try takeUUID(&rest)
            let offset = try takeUInt64(&rest)
            return .chunk(id: id, offset: offset, data: Data(rest))
        case .ack:
            let id = try takeUUID(&rest)
            let upTo = try takeUInt64(&rest)
            return .ack(id: id, receivedUpTo: upTo)
        case .complete:
            let id = try takeUUID(&rest)
            guard rest.count == 32 else { throw FileTransferError.badMessage }
            return .complete(id: id, sha256: Data(rest))
        case .cancel:
            return .cancel(id: try takeUUID(&rest))
        }
    }
}

public enum FileTransferError: Error, Equatable {
    case badMessage
    case tooLarge
    case io
    case checksum
    case notConnected
}

/// Strip path separators so a peer cannot write outside ~/Downloads/BlueComms.
public func sanitizeFileName(_ raw: String) -> String {
    let trimmed = raw.replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "file" : trimmed
}

func incomingInboxURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/BlueComms", isDirectory: true)
}

/// If "photo.png" exists, write "photo 2.png" instead of overwriting.
func uniqueDestination(directory: URL, name: String) -> URL {
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var url = directory.appendingPathComponent(name)
    var index = 2
    while FileManager.default.fileExists(atPath: url.path) {
        let stamped = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
        url = directory.appendingPathComponent(stamped)
        index += 1
    }
    return url
}

/// Big-endian 16-bit. Must use the original value, not value.bigEndian.
func uInt16Bytes(_ value: UInt16) -> [UInt8] {
    [UInt8(value >> 8), UInt8(truncatingIfNeeded: value)]
}

public func uInt64Bytes(_ value: UInt64) -> [UInt8] {
    var v = value.bigEndian
    return withUnsafeBytes(of: &v, Array.init)
}

func takeUUID(_ data: inout Data.SubSequence) throws -> UUID {
    guard data.count >= 16, let id = uuidFromBytes(Data(data.prefix(16))) else {
        throw FileTransferError.badMessage
    }
    data = data.dropFirst(16)
    return id
}

func takeUInt16(_ data: inout Data.SubSequence) throws -> UInt16 {
    guard data.count >= 2 else { throw FileTransferError.badMessage }
    let value = data.prefix(2).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    data = data.dropFirst(2)
    return value
}

func takeUInt64(_ data: inout Data.SubSequence) throws -> UInt64 {
    guard data.count >= 8 else { throw FileTransferError.badMessage }
    let value = data.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    data = data.dropFirst(8)
    return value
}
