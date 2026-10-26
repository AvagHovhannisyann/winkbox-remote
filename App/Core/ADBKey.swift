import Foundation
import Security

/// The RSA key this app uses to log in to the box's ADB service. The box asks once on the TV ("Allow USB
/// debugging?") and remembers the key after "Always allow"; later connections sign the box's challenge with it.
struct ADBKey {
    let privateKey: SecKey
    let publicKey: SecKey

    /// Loads the app's key from Application Support, creating it on first launch. A plain file (not the keychain)
    /// because sideloaded builds are re-signed every week and keychain access can change between signatures.
    static func loadOrCreate(directory: URL) throws -> ADBKey {
        let file = directory.appendingPathComponent("adbkey.der")
        if let der = try? Data(contentsOf: file), let key = try? fromPKCS1(der) {
            return key
        }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let der = SecKeyCopyExternalRepresentation(priv, &error) as Data? else {
            throw error!.takeRetainedValue() as Error
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try der.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return try fromPKCS1(der)
    }

    /// A key from a PKCS#1 RSAPrivateKey DER blob.
    static func fromPKCS1(_ der: Data) throws -> ADBKey {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &error),
              let pub = SecKeyCopyPublicKey(priv) else {
            throw error?.takeRetainedValue() as Error? ?? ADBError.badKey
        }
        return ADBKey(privateKey: priv, publicKey: pub)
    }

    /// A key from the PEM PKCS#8 file adb itself writes (~/.android/adbkey); used by the Mac test tool.
    static func fromPEM(_ pem: String) throws -> ADBKey {
        let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let pkcs8 = Data(base64Encoded: body) else { throw ADBError.badKey }
        // PrivateKeyInfo ::= SEQUENCE { version INTEGER, algorithm SEQUENCE, privateKey OCTET STRING }
        var outer = DER(Array(pkcs8))
        guard let info = outer.read(tag: 0x30) else { throw ADBError.badKey }
        var fields = DER(info)
        guard fields.read(tag: 0x02) != nil, fields.read(tag: 0x30) != nil,
              let pkcs1 = fields.read(tag: 0x04) else { throw ADBError.badKey }
        return try fromPKCS1(Data(pkcs1))
    }

    /// Signs the box's 20-byte AUTH token the way adb does: RSA PKCS#1 v1.5 over a SHA-1 DigestInfo of the token.
    func sign(token: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(privateKey, .rsaSignatureDigestPKCS1v15SHA1, token as CFData, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        return sig as Data
    }

    /// The public key in adb's own format (Android's mincrypt RSAPublicKey struct, base64) followed by a name. The
    /// box shows this key's fingerprint in its "Allow USB debugging?" dialog and stores it after "Always allow".
    func adbPublicKey(name: String) throws -> Data {
        guard let der = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { throw ADBError.badKey }
        // RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
        var outer = DER(Array(der))
        guard let seq = outer.read(tag: 0x30) else { throw ADBError.badKey }
        var fields = DER(seq)
        guard var modulus = fields.read(tag: 0x02), let exponent = fields.read(tag: 0x02) else { throw ADBError.badKey }
        while modulus.first == 0 { modulus.removeFirst() }
        guard modulus.count == 256 else { throw ADBError.badKey }

        let words = 64
        var n = [UInt32](repeating: 0, count: words)       // little-endian 32-bit words
        for i in 0..<words {
            let b = modulus.count - 4 * (i + 1)
            n[i] = UInt32(modulus[b]) << 24 | UInt32(modulus[b + 1]) << 16 | UInt32(modulus[b + 2]) << 8 | UInt32(modulus[b + 3])
        }

        // n0inv = -1 / n[0] mod 2^32 (Newton's iteration doubles the correct low bits each round).
        var inv: UInt32 = 1
        for _ in 0..<5 { inv = inv &* (2 &- n[0] &* inv) }
        let n0inv = 0 &- inv

        // rr = (2^2048)^2 mod n, by doubling 1 modulo n 4096 times.
        var rr = [UInt32](repeating: 0, count: words)
        rr[0] = 1
        for _ in 0..<4096 {
            var carry: UInt32 = 0
            for i in 0..<words {
                let v = rr[i]
                rr[i] = v << 1 | carry
                carry = v >> 31
            }
            if carry == 1 || !Self.less(rr, n) { Self.subtract(&rr, n) }
        }

        var e: UInt32 = 0
        for b in exponent { e = e << 8 | UInt32(b) }

        var blob = Data()
        func put(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { blob.append(contentsOf: $0) } }
        put(UInt32(words))
        put(n0inv)
        n.forEach(put)
        rr.forEach(put)
        put(e)

        var out = Data(blob.base64EncodedString().utf8)
        out.append(contentsOf: Array(" \(name)".utf8))
        out.append(0)
        return out
    }

    private static func less(_ a: [UInt32], _ b: [UInt32]) -> Bool {
        for i in stride(from: a.count - 1, through: 0, by: -1) where a[i] != b[i] {
            return a[i] < b[i]
        }
        return false
    }

    private static func subtract(_ a: inout [UInt32], _ b: [UInt32]) {
        var borrow: UInt64 = 0
        for i in 0..<a.count {
            let d = UInt64(a[i]) &- UInt64(b[i]) &- borrow
            a[i] = UInt32(truncatingIfNeeded: d)
            borrow = d >> 63
        }
    }
}

/// A minimal DER reader: enough to walk the RSA key structures above.
struct DER {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func read(tag: UInt8) -> [UInt8]? {
        guard index + 2 <= bytes.count, bytes[index] == tag else { return nil }
        index += 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count <= 4, index + count <= bytes.count else { return nil }
            length = 0
            for _ in 0..<count {
                length = length << 8 | Int(bytes[index])
                index += 1
            }
        }
        guard index + length <= bytes.count else { return nil }
        defer { index += length }
        return Array(bytes[index..<index + length])
    }
}
