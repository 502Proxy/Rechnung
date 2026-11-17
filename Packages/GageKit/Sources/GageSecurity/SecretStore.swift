import Foundation
import Security

public enum SecretKey: String, CaseIterable, Sendable {
    /// Symmetric key that encrypts the local database.
    case databaseKey = "database-key.v1"
    /// bunq API key, as entered by the user.
    case bunqAPIKey = "bunq-api-key"
    /// RSA private key for signing bunq requests (PKCS#1 DER).
    case bunqClientPrivateKey = "bunq-client-private-key"
    /// Installation token and server public key from the bunq installation.
    case bunqInstallation = "bunq-installation"
}

public enum SecretStoreError: Error, Equatable, Sendable, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Schlüsselbund-Fehler: \(message)"
        case .invalidData:
            return "Der Eintrag im Schlüsselbund ist beschädigt."
        }
    }
}

public protocol SecretStore: Sendable {
    func data(for key: SecretKey) throws -> Data?
    func set(_ data: Data, for key: SecretKey) throws
    func remove(_ key: SecretKey) throws
}

/// Stores secrets in the macOS Keychain.
///
/// Items are only readable while the Mac is unlocked, stay on this device and
/// are never synced to iCloud (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
/// In the signed, sandboxed app they also go to the data protection keychain,
/// which isolates them by app identifier.
public struct KeychainSecretStore: SecretStore {
    private let service: String
    private let useDataProtectionKeychain: Bool

    public init(service: String, useDataProtectionKeychain: Bool = true) {
        self.service = service
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    public func data(for key: SecretKey) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw SecretStoreError.invalidData }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    public func set(_ data: Data, for key: SecretKey) throws {
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let addStatus = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecretStoreError.unexpectedStatus(addStatus) }
        default:
            throw SecretStoreError.unexpectedStatus(updateStatus)
        }
    }

    public func remove(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: SecretKey) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}

/// Keeps secrets in memory only, for tests and SwiftUI previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SecretKey: Data] = [:]

    public init() {}

    public func data(for key: SecretKey) throws -> Data? {
        lock.withLock { storage[key] }
    }

    public func set(_ data: Data, for key: SecretKey) throws {
        lock.withLock { storage[key] = data }
    }

    public func remove(_ key: SecretKey) throws {
        _ = lock.withLock { storage.removeValue(forKey: key) }
    }
}
