import CryptoKit
import Foundation

// Two JSON bodies a later menu-bar change can send.
//
// This device mints an X25519 keypair and keeps the private key on the
// returned value. Registration is a label, a platform, and the public key.
// The mailbox body is one ciphertext. The wire layout matches
// experiments/sealed-mailbox/seal.ts:
//   version(1) || ephemeral public(32) || nonce(12) || aes-256-gcm body || tag(16)
// HKDF-SHA256 salt is the ephemeral public key. Info is mesh-sealed-mailbox-v1.
// AAD is version || ephemeral public. The mailbox string is base64url of that.
// Nothing here writes a key file or dials out.

struct DeviceSyncBodies: Encodable {
    let registration: String
    let mailbox: String
    let privateKey: Curve25519.KeyAgreement.PrivateKey

    private enum CodingKeys: String, CodingKey {
        case registration
        case mailbox
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(registration, forKey: .registration)
        try container.encode(mailbox, forKey: .mailbox)
    }

    static let platforms: Set<String> = ["web", "ios", "watchos", "macos", "linux"]

    enum Failure: Error {
        case invalidLabel
        case invalidPlatform
        case sealFailed
    }

    static func build(
        label: String,
        platform: String,
        recipientPublicKey: Data,
        plaintext: Data
    ) throws -> DeviceSyncBodies {
        guard (1...64).contains(label.count) else { throw Failure.invalidLabel }
        guard platforms.contains(platform) else { throw Failure.invalidPlatform }
        guard !plaintext.isEmpty else { throw Failure.sealFailed }

        let device = Curve25519.KeyAgreement.PrivateKey()
        let publicRaw = device.publicKey.rawRepresentation
        guard publicRaw.count == Seal.pubLen else { throw Failure.sealFailed }
        // Key order matches the node client's JSON.stringify insertion order.
        // JSONEncoder's synthesized object order is not that order.
        let registration = try object([
            ("label", label),
            ("platform", platform),
            ("public_key", Seal.base64urlEncode(publicRaw)),
        ])
        let ciphertext = try Seal.pack(plaintext, recipientPublic: recipientPublicKey)
        let mailbox = try object([("ciphertext", ciphertext)])
        return DeviceSyncBodies(
            registration: registration,
            mailbox: mailbox,
            privateKey: device
        )
    }

    private static func object(_ fields: [(String, String)]) throws -> String {
        var parts: [String] = []
        for (key, value) in fields {
            parts.append("\(try jsonString(key)):\(try jsonString(value))")
        }
        let text = "{\(parts.joined(separator: ","))}"
        guard !text.isEmpty else { throw Failure.sealFailed }
        return text
    }

    private static func jsonString(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw Failure.sealFailed
        }
        return text
    }

    private enum Seal {
        static let version: UInt8 = 1
        static let pubLen = 32
        static let nonceLen = 12
        static let tagLen = 16
        static let info = Data("mesh-sealed-mailbox-v1".utf8)
        static let maxChars = 16384

        static func base64urlEncode(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        static func deriveKey(shared: SharedSecret, salt: Data) -> SymmetricKey {
            shared.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: salt,
                sharedInfo: info,
                outputByteCount: 32
            )
        }

        static func pack(_ plaintext: Data, recipientPublic rawPublic: Data) throws -> String {
            guard rawPublic.count == pubLen else { throw Failure.sealFailed }
            let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: rawPublic)
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let ephRaw = ephemeral.publicKey.rawRepresentation
            guard ephRaw.count == pubLen else { throw Failure.sealFailed }
            let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
            let key = deriveKey(shared: shared, salt: ephRaw)
            let nonce = AES.GCM.Nonce()
            var aad = Data([version])
            aad.append(ephRaw)
            let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
            let nonceData = nonce.withUnsafeBytes { Data($0) }
            guard nonceData.count == nonceLen, sealed.tag.count == tagLen else {
                throw Failure.sealFailed
            }
            var packed = Data([version])
            packed.append(ephRaw)
            packed.append(nonceData)
            packed.append(sealed.ciphertext)
            packed.append(sealed.tag)
            let ciphertext = base64urlEncode(packed)
            guard !ciphertext.isEmpty, ciphertext.count <= maxChars else {
                throw Failure.sealFailed
            }
            return ciphertext
        }
    }
}
