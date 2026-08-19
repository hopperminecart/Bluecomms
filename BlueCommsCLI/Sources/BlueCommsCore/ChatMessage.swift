import Foundation

public enum MessageDelivery: String, Codable, Sendable {
    case sent
    case queued
}

public enum MessageKind: String, Codable, Sendable {
    case text
    case file
}

public struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let peerID: String
    public let text: String
    public let isLocal: Bool
    public let sentAt: Date
    public var delivery: MessageDelivery
    public var kind: MessageKind
    public var fileName: String?
    public var fileSize: UInt64?
    public var filePath: String?
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

public struct ConversationSnapshot: Codable, Equatable, Sendable {
    public var conversations: [String: [ChatMessage]]
    public var outboundIDs: [UUID]

    public init(conversations: [String: [ChatMessage]] = [:], outboundIDs: [UUID] = []) {
        self.conversations = conversations
        self.outboundIDs = outboundIDs
    }
}
