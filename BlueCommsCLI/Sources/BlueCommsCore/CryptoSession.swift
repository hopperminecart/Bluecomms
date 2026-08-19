import CryptoKit
import Foundation

public enum WireType: UInt8, Sendable {
    case handshake = 0x01
    case ciphertext = 0x02
    case file = 0x03
}

public enum CryptoError: Error, Equatable, Sendable {
    case notEstablished
    case malformedCiphertext
    case handshakeTooShort
    case unsupportedProtocol(UInt8)
    case invalidPublicKey
    case tofuMismatch
}

public struct HandshakePayload: Equatable, Sendable {
    public static let protoVersion: UInt8 = 1
    public static let wireSize = 1 + 16 + 32

    public let peerID: UUID
    public let publicKey: Data

    public init(peerID: UUID, publicKey: Data) {
        self.peerID = peerID
        self.publicKey = publicKey
    }

    public func encoded() -> Data {
        var data = Data([HandshakePayload.protoVersion])
        data.append(contentsOf: uuidBytes(peerID))
        data.append(publicKey)
        return data
    }

    public static func decode(_ data: Data) throws -> HandshakePayload {
        guard data.count == wireSize else { throw CryptoError.handshakeTooShort }
        let proto = data[data.startIndex]
        guard proto == protoVersion else { throw CryptoError.unsupportedProtocol(proto) }
        let uuidData = data.subdata(in: data.index(data.startIndex, offsetBy: 1)..<data.index(data.startIndex, offsetBy: 17))
        let key = data.subdata(in: data.index(data.startIndex, offsetBy: 17)..<data.endIndex)
        guard key.count == 32 else { throw CryptoError.invalidPublicKey }
        guard let peerID = uuidFromBytes(uuidData) else { throw CryptoError.handshakeTooShort }
        return HandshakePayload(peerID: peerID, publicKey: key)
    }
}

public struct CryptoSession: Sendable {
    private let localPrivateKey: Curve25519.KeyAgreement.PrivateKey
    private var sendKey: SymmetricKey?
    private var receiveKey: SymmetricKey?
    private var sendCounter: UInt64 = 0

    public var isEstablished: Bool { sendKey != nil }

    public init(localPrivateKey: Curve25519.KeyAgreement.PrivateKey) {
        self.localPrivateKey = localPrivateKey
    }

    public mutating func establish(peerPublicKey: Data) throws {
        let peer: Curve25519.KeyAgreement.PublicKey
        do {
            peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        } catch {
            throw CryptoError.invalidPublicKey
        }

        let localPublic = localPrivateKey.publicKey.rawRepresentation
        if localPublic == peerPublicKey {
            throw CryptoError.invalidPublicKey
        }

        let secret: SharedSecret
        do {
            secret = try localPrivateKey.sharedSecretFromKeyAgreement(with: peer)
        } catch {
            throw CryptoError.invalidPublicKey
        }

        let lowToHigh = deriveKey(secret, info: "bluecomms-v1-l2h")
        let highToLow = deriveKey(secret, info: "bluecomms-v1-h2l")

        if localPublic.lexicographicallyPrecedes(peerPublicKey) {
            sendKey = lowToHigh
            receiveKey = highToLow
        } else {
            sendKey = highToLow
            receiveKey = lowToHigh
        }
        sendCounter = 0
    }

    public mutating func seal(_ plaintext: Data) throws -> Data {
        guard let sendKey else { throw CryptoError.notEstablished }
        let nonceData = nonceBytes(sendCounter)
        sendCounter += 1
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(plaintext, using: sendKey, nonce: nonce)
        return nonceData + sealed.ciphertext + sealed.tag
    }

    public func open(_ blob: Data) throws -> Data {
        guard let receiveKey else { throw CryptoError.notEstablished }
        guard blob.count >= 12 + 16 else { throw CryptoError.malformedCiphertext }
        let nonceData = blob.prefix(12)
        let tag = blob.suffix(16)
        let ciphertext = blob.dropFirst(12).dropLast(16)
        let box = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: nonceData),
            ciphertext: Data(ciphertext),
            tag: Data(tag)
        )
        return try AES.GCM.open(box, using: receiveKey)
    }

    private func deriveKey(_ secret: SharedSecret, info: String) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("bluecomms-v1".utf8),
            sharedInfo: Data(info.utf8),
            outputByteCount: 32
        )
    }

    private func nonceBytes(_ counter: UInt64) -> Data {
        var data = Data(count: 12)
        var value = counter.bigEndian
        Swift.withUnsafeBytes(of: &value) { bytes in
            data.replaceSubrange(4..<12, with: bytes)
        }
        return data
    }
}

func uuidBytes(_ uuid: UUID) -> [UInt8] {
    let u = uuid.uuid
    return [
        u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
        u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15,
    ]
}

func uuidFromBytes(_ data: Data) -> UUID? {
    guard data.count == 16 else { return nil }
    let b = [UInt8](data)
    return UUID(uuid: (
        b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
        b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
    ))
}

public func keyFingerprint(_ publicKey: Data) -> String {
    let digest = SHA256.hash(data: publicKey)
    let hex = digest.prefix(6).map { String(format: "%02X", $0) }.joined()
    let chars = Array(hex)
    return "\(String(chars[0..<4]))-\(String(chars[4..<8]))-\(String(chars[8..<12]))"
}
