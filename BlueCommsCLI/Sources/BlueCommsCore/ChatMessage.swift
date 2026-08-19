import Foundation

public enum MessageDelivery: String, Codable, Sendable {
    case sent
    case queued
}

public struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let peerID: String
    public let text: String
    public let isLocal: Bool
    public let sentAt: Date
    public var delivery: MessageDelivery

    public init(
        id: UUID = UUID(),
        peerID: String,
        text: String,
        isLocal: Bool,
        sentAt: Date = Date(),
        delivery: MessageDelivery = .sent
    ) {
        self.id = id
        self.peerID = peerID
        self.text = text
        self.isLocal = isLocal
        self.sentAt = sentAt
        self.delivery = delivery
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
