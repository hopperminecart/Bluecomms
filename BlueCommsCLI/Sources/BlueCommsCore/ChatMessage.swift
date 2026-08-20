//
//  ChatMessage.swift
//
//  Why this file exists:
//    One row in a thread — text or a file card. Shared by the Mac UI and
//    MessageArchive. Codable so history survives a restart (PR #3). File
//    fields were added in PR #5.
//
//  File bytes are NOT stored here. We keep name / size / path / progress.
//  The actual bytes live on disk (source file, or ~/Downloads/BlueComms).
//

import Foundation

/// sent = on the wire (or already delivered). queued = waiting for a session.
public enum MessageDelivery: String, Codable, Sendable {
    case sent
    case queued
}

public enum MessageKind: String, Codable, Sendable {
    case text
    case file
}

/// One bubble in the thread. `peerID` is the other Mac's device UUID string.
public struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Other Mac's device UUID string (conversation key).
    public let peerID: String
    /// Chat text, or the file name when kind == .file.
    public let text: String
    /// true = we sent it (right side). false = they sent it.
    public let isLocal: Bool
    public let sentAt: Date
    public var delivery: MessageDelivery
    public var kind: MessageKind
    public var fileName: String?
    public var fileSize: UInt64?
    /// Local path: the file we sent, or ~/Downloads/BlueComms/... when received.
    public var filePath: String?
    /// Ties UI progress updates to this row.
    public var transferID: UUID?
    public var progress: Double
    public var fileState: FileTransferState?

    public init(
        id: UUID = UUID(),
        peerID: String,
        text: String,
        isLocal: Bool,
        sentAt: Date = Date(),
        delivery: MessageDelivery = .sent,
        kind: MessageKind = .text,
        fileName: String? = nil,
        fileSize: UInt64? = nil,
        filePath: String? = nil,
        transferID: UUID? = nil,
        progress: Double = 1,
        fileState: FileTransferState? = nil
    ) {
        self.id = id
        self.peerID = peerID
        self.text = text
        self.isLocal = isLocal
        self.sentAt = sentAt
        self.delivery = delivery
        self.kind = kind
        self.fileName = fileName
        self.fileSize = fileSize
        self.filePath = filePath
        self.transferID = transferID
        self.progress = progress
        self.fileState = fileState
    }

    /// Older archives have no file keys. Missing fields become a text message.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        peerID = try container.decode(String.self, forKey: .peerID)
        text = try container.decode(String.self, forKey: .text)
        isLocal = try container.decode(Bool.self, forKey: .isLocal)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        delivery = try container.decode(MessageDelivery.self, forKey: .delivery)
        kind = try container.decodeIfPresent(MessageKind.self, forKey: .kind) ?? .text
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        fileSize = try container.decodeIfPresent(UInt64.self, forKey: .fileSize)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        transferID = try container.decodeIfPresent(UUID.self, forKey: .transferID)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 1
        fileState = try container.decodeIfPresent(FileTransferState.self, forKey: .fileState)
    }
}

/// On-disk chat history. `outboundIDs` kept so older archive files still decode.
public struct ConversationSnapshot: Codable, Equatable, Sendable {
    public var conversations: [String: [ChatMessage]]
    public var outboundIDs: [UUID]

    public init(conversations: [String: [ChatMessage]] = [:], outboundIDs: [UUID] = []) {
        self.conversations = conversations
        self.outboundIDs = outboundIDs
    }
}
