import CryptoKit
import Foundation

/// AES-GCM sealing and keyed hashing with subkeys derived from the master key (SECURITY_MODEL §3).
public struct CryptoBox: Sendable {
    private let encKey: SymmetricKey
    private let hashKey: SymmetricKey

    public init(masterKey: SymmetricKey) {
        let salt = Data("ClipFlow.v1".utf8)
        encKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: salt,
                                        info: Data("enc".utf8), outputByteCount: 32)
        hashKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: salt,
                                         info: Data("hash".utf8), outputByteCount: 32)
    }

    /// Returns nonce ‖ ciphertext ‖ tag. `aad` binds the ciphertext to its row and column.
    public func seal(_ plaintext: Data, aad: String) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: encKey, authenticating: Data(aad.utf8))
        guard let combined = box.combined else { throw CryptoKitError.incorrectParameterSize }
        return combined
    }

    public func open(_ sealed: Data, aad: String) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: sealed)
        return try AES.GCM.open(box, using: encKey, authenticating: Data(aad.utf8))
    }

    /// HMAC-SHA256(hashKey, kind ‖ 0x00 ‖ canonical) — keyed so the plaintext column can't confirm guesses.
    public func contentHash(kind: ClipKind, canonical: Data) -> Data {
        var message = Data(kind.rawValue.utf8)
        message.append(0)
        message.append(canonical)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: hashKey))
    }
}
