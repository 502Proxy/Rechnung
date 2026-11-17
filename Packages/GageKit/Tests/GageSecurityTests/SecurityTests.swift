import CryptoKit
import Foundation
@testable import GageSecurity
import Testing

@Suite("Security")
struct SecurityTests {
    @Test("Encrypted data can be read back")
    func roundTrip() throws {
        let encryptor = DataEncryptor(key: SymmetricKey(size: .bits256))
        let plaintext = Data("Rechnung 2026-015 über 860,00 €".utf8)
        let sealed = try encryptor.seal(plaintext)
        #expect(sealed.prefix(4) == Data("GAGE".utf8))
        #expect(sealed.range(of: plaintext) == nil)
        #expect(try encryptor.open(sealed) == plaintext)
    }

    @Test("The same input never produces the same ciphertext")
    func randomNonce() throws {
        let encryptor = DataEncryptor(key: SymmetricKey(size: .bits256))
        let plaintext = Data("gleich".utf8)
        #expect(try encryptor.seal(plaintext) != encryptor.seal(plaintext))
    }

    @Test("Altered data is rejected")
    func tamperDetection() throws {
        let encryptor = DataEncryptor(key: SymmetricKey(size: .bits256))
        var sealed = try encryptor.seal(Data("Gewinn 12.445,55 €".utf8))
        sealed[sealed.count - 1] ^= 0x01
        #expect(throws: EncryptionError.authenticationFailed) { try encryptor.open(sealed) }
    }

    @Test("The wrong key cannot decrypt")
    func wrongKey() throws {
        let sealed = try DataEncryptor(key: SymmetricKey(size: .bits256)).seal(Data("geheim".utf8))
        #expect(throws: EncryptionError.authenticationFailed) {
            try DataEncryptor(key: SymmetricKey(size: .bits256)).open(sealed)
        }
    }

    @Test("Unknown file formats and versions are refused")
    func headerChecks() throws {
        let encryptor = DataEncryptor(key: SymmetricKey(size: .bits256))
        #expect(throws: EncryptionError.unknownFormat) { try encryptor.open(Data("{\"plain\":true}".utf8)) }
        var sealed = try encryptor.seal(Data("x".utf8))
        sealed[4] = 99
        #expect(throws: EncryptionError.unsupportedVersion(99)) { try encryptor.open(sealed) }
    }

    @Test("The database key is created once and then reused")
    func keyProvisioning() throws {
        let store = InMemorySecretStore()
        let first = try DataEncryptor.loadingOrCreatingKey(in: store)
        let sealed = try first.seal(Data("persistent".utf8))
        let second = try DataEncryptor.loadingOrCreatingKey(in: store)
        #expect(try second.open(sealed) == Data("persistent".utf8))
        #expect(try store.data(for: .databaseKey)?.count == 32)
    }

    @Test("SHA-256 matches the known test vector")
    func digest() {
        #expect(SHA256Digest().sha256Hex(of: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("Auto-lock after inactivity, at least one minute")
    func lockPolicy() {
        let start = Date(timeIntervalSince1970: 0)
        let policy = AppLockPolicy(isEnabled: true, idleTimeout: 300)
        #expect(!policy.shouldLock(lastActivity: start, now: start.addingTimeInterval(299)))
        #expect(policy.shouldLock(lastActivity: start, now: start.addingTimeInterval(300)))
        #expect(AppLockPolicy(isEnabled: true, idleTimeout: 1).idleTimeout == 60)
        #expect(!AppLockPolicy(isEnabled: false, idleTimeout: 60).shouldLock(lastActivity: start, now: .now))
    }
}
