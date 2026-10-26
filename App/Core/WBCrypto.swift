import Foundation
import CryptoKit
import Security

/// Primitives for pairing with the TV and for the sealed settings message. The wire formats match the TV's Java side:
/// x9.63 P-256 public keys, HKDF-SHA256, HMAC-SHA256, and AES-256-GCM boxes as nonce || ciphertext || tag.
enum WBCrypto {
    static func hmac(_ key: Data, _ parts: Data...) -> Data {
        var h = HMAC<SHA256>(key: SymmetricKey(data: key))
        for p in parts { h.update(data: p) }
        return Data(h.finalize())
    }

    static func equal(_ a: Data, _ b: Data) -> Bool {
        a.count == b.count && zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// Seals a settings payload (an API key, say) so only this phone and the TV can read it.
    static func seal(_ plain: Data, secret: Data, aad: Data) throws -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret), salt: Data(),
                                         info: Data("winkbox seal v1".utf8), outputByteCount: 32)
        guard let combined = try AES.GCM.seal(plain, using: key, authenticating: aad).combined else { throw URLError(.cannotParseResponse) }
        return combined
    }

    /// Everything the phone needs from a pairing exchange: the proof for the TV, and the secret both sides derive.
    struct Pairing {
        let phonePub: Data
        let proof: Data
        let secret: Data
        let tvProof: (Data) -> Bool
    }

    /// The phone's half of pairing: proves it knows the code shown on the TV and derives the shared secret.
    static func pair(code: String, tvPub tvPubBytes: Data, nonce: Data) throws -> Pairing {
        let priv = P256.KeyAgreement.PrivateKey()
        let phonePub = priv.publicKey.x963Representation
        let proof = hmac(Data(code.utf8), Data("pair1".utf8), phonePub, tvPubBytes, nonce)
        let tvPub = try P256.KeyAgreement.PublicKey(x963Representation: tvPubBytes)
        let shared = try priv.sharedSecretFromKeyAgreement(with: tvPub)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: nonce, sharedInfo: Data("winkbox pair v1".utf8), outputByteCount: 32)
        let secret = key.withUnsafeBytes { Data($0) }
        return Pairing(phonePub: phonePub, proof: proof, secret: secret,
                       tvProof: { equal(hmac(secret, Data("tv-ok".utf8), nonce), $0) })
    }
}

/// What the phone keeps after pairing. Stored in the Keychain (or app defaults where the Keychain isn't available to a
/// sideloaded build).
struct PairedIdentity: Codable, Equatable {
    let deviceId: String
    let secret: Data
}

enum Keychain {
    private static let service = "com.winkbox.remote"

    static func save(_ data: Data, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(data, forKey: "kc." + account)   // sideloaded builds can lack Keychain entitlements
        }
    }

    static func load(_ account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data { return d }
        return UserDefaults.standard.data(forKey: "kc." + account)
    }

    static func delete(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "kc." + account)
    }
}
