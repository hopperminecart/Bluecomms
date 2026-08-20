//
//  FrameCodec.swift
//
//  Why this file exists:
//    TCP is a byte stream. Two sends can arrive as one blob, or one send can
//    split mid-message. Without a length prefix, chat looked garbled and
//    files could not be reassembled (fixed in PR #1).
//
//  Format: 4-byte big-endian size + payload. Cap 512 KB so a bad peer cannot
//  ask us to allocate gigabytes. File transfer uses many of these frames.
//

import Foundation

public enum FrameError: Error, Equatable, Sendable {
    case payloadTooLarge(Int)
    case declaredLengthTooLarge(UInt32)
}

public enum FrameCodec: Sendable {
    public static let headerSize = 4
    /// 512 KB. Must stay in sync with FileMessage.chunkSize + crypto overhead.
    public static let maxPayloadSize = 524_288

    /// Prefix `payload` with its big-endian length.
    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maxPayloadSize else {
            throw FrameError.payloadTooLarge(payload.count)
        }
        var header = Data(count: headerSize)
        let length = UInt32(payload.count).bigEndian
        Swift.withUnsafeBytes(of: length) { bytes in
            header.replaceSubrange(0..<headerSize, with: bytes)
        }
        return header + payload
    }

    public static func readUInt32BE(_ data: Data) -> UInt32 {
        data.prefix(headerSize).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

/// Incremental reader. Feed whatever TCP gave you; get zero or more payloads.
public final class FrameDecoder: @unchecked Sendable {
    private var buffer = Data()

    public init() {}

    /// Append a TCP chunk. Returns complete payloads only; leftover bytes stay buffered.
    public func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []

        while buffer.count >= FrameCodec.headerSize {
            let length = FrameCodec.readUInt32BE(buffer)
            guard length <= UInt32(FrameCodec.maxPayloadSize) else {
                buffer.removeAll(keepingCapacity: false)
                throw FrameError.declaredLengthTooLarge(length)
            }
            let total = FrameCodec.headerSize + Int(length)
            guard buffer.count >= total else { break }
            frames.append(buffer.subdata(in: FrameCodec.headerSize..<total))
            buffer.removeSubrange(0..<total)
        }

        return frames
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}
