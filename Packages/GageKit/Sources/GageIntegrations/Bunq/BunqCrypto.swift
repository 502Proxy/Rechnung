import Foundation
import Security

public enum BunqError: Error, Equatable, Sendable, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case missingServerSignature
    case invalidServerSignature
    case untrustedHost(String)
    case api(operation: String, status: Int, message: String)
    case crypto(String)
    case unexpectedPayload(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Es ist kein bunq-API-Schlüssel hinterlegt."
        case .invalidResponse: "bunq hat keine gültige Antwort geliefert."
        case .missingServerSignature, .invalidServerSignature:
            "Die Antwort von bunq war nicht korrekt signiert und wurde verworfen."
        case let .untrustedHost(host): "Verbindung zu \(host) wurde blockiert."
        case let .api(operation, status, message) where status == 400 || status == 401 || status == 403:
            """
            bunq hat „\(operation)“ abgelehnt (\(status)): \(message)
            Prüfe den API-Schlüssel. Schlüssel aus der bunq-Sandbox beginnen mit „sandbox_“, \
            echte Schlüssel erstellst du in der bunq-App. Wurde der Schlüssel auf bestimmte \
            IP-Adressen beschränkt, muss deine aktuelle IP-Adresse erlaubt sein.
            """
        case let .api(operation, status, message): "bunq hat „\(operation)“ abgelehnt (\(status)): \(message)"
        case let .crypto(message): "Kryptografiefehler: \(message)"
        case let .unexpectedPayload(detail): "Unerwartete Antwort von bunq (\(detail))."
        }
    }
}

/// The client's RSA key pair for bunq.
///
/// bunq requires request bodies to be signed with RSA-SHA256 and signs its own
/// responses with the server key received during installation.
struct BunqKeyPair {
    let privateKey: SecKey

    static func generate() throws -> BunqKeyPair {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw BunqError.crypto(Self.describe(error))
        }
        return BunqKeyPair(privateKey: key)
    }

    /// Restores a key from its PKCS#1 representation (as stored in the Keychain).
    static func restore(from data: Data) throws -> BunqKeyPair {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            throw BunqError.crypto(Self.describe(error))
        }
        return BunqKeyPair(privateKey: key)
    }

    func exportPrivateKey() throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw BunqError.crypto(Self.describe(error))
        }
        return data
    }

    /// Public key as X.509 SubjectPublicKeyInfo in PEM format, the form bunq expects.
    func publicKeyPEM() throws -> String {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { throw BunqError.crypto("Kein öffentlicher Schlüssel") }
        var error: Unmanaged<CFError>?
        guard let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw BunqError.crypto(Self.describe(error))
        }
        return PEM.encode(DER.subjectPublicKeyInfo(wrappingRSAPublicKey: pkcs1), label: "PUBLIC KEY")
    }

    func sign(_ data: Data) throws -> String {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) as Data? else {
            throw BunqError.crypto(Self.describe(error))
        }
        return signature.base64EncodedString()
    }

    static func verify(signatureBase64: String, data: Data, publicKeyPEM: String) -> Bool {
        guard let signature = Data(base64Encoded: signatureBase64),
              let spki = PEM.decode(publicKeyPEM),
              let pkcs1 = DER.rsaPublicKey(fromSubjectPublicKeyInfo: spki)
        else { return false }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil) else { return false }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, signature as CFData, nil)
    }

    private static func describe(_ error: Unmanaged<CFError>?) -> String {
        guard let error else { return "unbekannt" }
        return (error.takeRetainedValue() as any Error).localizedDescription
    }
}

enum PEM {
    static func encode(_ der: Data, label: String) -> String {
        let body = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(label)-----\n\(body)\n-----END \(label)-----\n"
    }

    static func decode(_ pem: String) -> Data? {
        let body = pem
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: body)
    }
}

/// Just enough DER handling to convert between PKCS#1 and SubjectPublicKeyInfo.
enum DER {
    /// AlgorithmIdentifier for rsaEncryption (OID 1.2.840.113549.1.1.1) with NULL parameters.
    private static let rsaAlgorithmIdentifier: [UInt8] = [
        0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00,
    ]

    static func subjectPublicKeyInfo(wrappingRSAPublicKey pkcs1: Data) -> Data {
        let bitString = element(tag: 0x03, content: Data([0x00]) + pkcs1)
        return element(tag: 0x30, content: Data(rsaAlgorithmIdentifier) + bitString)
    }

    static func rsaPublicKey(fromSubjectPublicKeyInfo spki: Data) -> Data? {
        let bytes = [UInt8](spki)
        guard let outer = read(bytes, at: 0), outer.tag == 0x30,
              let algorithm = read(bytes, at: outer.contentStart), algorithm.tag == 0x30,
              Array(bytes[algorithm.headerStart..<algorithm.end]) == rsaAlgorithmIdentifier,
              let bitString = read(bytes, at: algorithm.end), bitString.tag == 0x03,
              bitString.end <= outer.end,
              bitString.contentStart < bitString.end, bytes[bitString.contentStart] == 0x00
        else { return nil }
        return Data(bytes[(bitString.contentStart + 1)..<bitString.end])
    }

    private struct Element {
        let tag: UInt8
        let headerStart: Int
        let contentStart: Int
        let end: Int
    }

    private static func read(_ bytes: [UInt8], at offset: Int) -> Element? {
        guard offset + 1 < bytes.count else { return nil }
        let tag = bytes[offset]
        var cursor = offset + 1
        let first = Int(bytes[cursor])
        cursor += 1
        var length = first
        if first & 0x80 != 0 {
            let count = first & 0x7F
            guard (1...4).contains(count), cursor + count <= bytes.count else { return nil }
            length = bytes[cursor..<(cursor + count)].reduce(0) { ($0 << 8) | Int($1) }
            cursor += count
        }
        guard length >= 0, cursor + length <= bytes.count else { return nil }
        return Element(tag: tag, headerStart: offset, contentStart: cursor, end: cursor + length)
    }

    private static func element(tag: UInt8, content: Data) -> Data {
        var data = Data([tag])
        let length = content.count
        if length < 0x80 {
            data.append(UInt8(length))
        } else {
            var lengthBytes: [UInt8] = []
            var remaining = length
            while remaining > 0 {
                lengthBytes.insert(UInt8(remaining & 0xFF), at: 0)
                remaining >>= 8
            }
            data.append(0x80 | UInt8(lengthBytes.count))
            data.append(contentsOf: lengthBytes)
        }
        data.append(content)
        return data
    }
}
