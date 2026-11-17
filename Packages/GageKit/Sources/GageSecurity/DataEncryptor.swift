import CryptoKit
import Foundation
import GageCore

public enum EncryptionError: Error, Equatable, Sendable, LocalizedError {
    case unknownFormat
    case unsupportedVersion(UInt8)
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .unknownFormat: "Die Datei ist keine Gage-Datenbank."
        case let .unsupportedVersion(version): "Die Datenbank hat ein unbekanntes Format (Version \(version))."
        case .authenticationFailed: "Die Datenbank konnte nicht entschlüsselt werden. Sie wurde verändert oder der Schlüssel fehlt."
        }
    }
}

/// Encrypts the local database with AES-256-GCM.
///
/// Layout: `"GAGE"` (4 bytes) · version (1 byte) · nonce · ciphertext · tag.
/// The header is authenticated as associated data, so it cannot be swapped
/// without detection. The key never leaves the Keychain except while in use.
public struct DataEncryptor: Sendable {
    static let magic = Data("GAGE".utf8)
    static let version: UInt8 = 1

    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    /// Loads the key from `store`, or generates a new 256-bit key on first launch.
    public static func loadingOrCreatingKey(in store: any SecretStore) throws -> DataEncryptor {
        if let existing = try store.data(for: .databaseKey) {
            guard existing.count == 32 else { throw SecretStoreError.invalidData }
            return DataEncryptor(key: SymmetricKey(data: existing))
        }
        let key = SymmetricKey(size: .bits256)
        try store.set(key.withUnsafeBytes { Data($0) }, for: .databaseKey)
        return DataEncryptor(key: key)
    }

    public func seal(_ plaintext: Data) throws -> Data {
        let header = Self.header
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: header)
        guard let combined = box.combined else { throw EncryptionError.unknownFormat }
        return header + combined
    }

    public func open(_ sealed: Data) throws -> Data {
        guard sealed.count > Self.magic.count + 1, sealed.prefix(Self.magic.count) == Self.magic else {
            throw EncryptionError.unknownFormat
        }
        let version = sealed[sealed.startIndex + Self.magic.count]
        guard version == Self.version else { throw EncryptionError.unsupportedVersion(version) }
        do {
            let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(Self.magic.count + 1))
            return try AES.GCM.open(box, using: key, authenticating: Self.header)
        } catch {
            throw EncryptionError.authenticationFailed
        }
    }

    private static var header: Data {
        magic + Data([version])
    }
}

/// SHA-256 via CryptoKit, for audit entries and archive checks.
public struct SHA256Digest: DigestProviding {
    public init() {}

    public func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
