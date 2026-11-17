import CryptoKit
import Foundation
import GageCore
@testable import GagePersistence
import GageSecurity
import Testing

@Suite("Persistence")
struct PersistenceTests {
    private final class TemporaryDirectory {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory.appending(path: "gage-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            // Archived files are locked. Unlock them so cleanup can delete them.
            if let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let file as URL in files {
                    try? FileManager.default.setAttributes(
                        [.immutable: false, .posixPermissions: 0o700],
                        ofItemAtPath: file.path(percentEncoded: false)
                    )
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private let encryptor = DataEncryptor(key: SymmetricKey(size: .bits256))

    @Test("Data survives saving and loading and is not stored as plaintext")
    func encryptedRoundTrip() async throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "store/gage.store")
        let repository = EncryptedFileRepository(fileURL: file, encryptor: encryptor)

        var data = AppData()
        data.profile.name = "Max Beispiel"
        data.profile.taxNumber = "43/123/45678"
        try await repository.save(data)

        let raw = try Data(contentsOf: file)
        #expect(raw.range(of: Data("Max Beispiel".utf8)) == nil)
        #expect(raw.range(of: Data("43/123/45678".utf8)) == nil)
        #expect(try await repository.load() == data)

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("Without a store the app starts empty")
    func missingStore() async throws {
        let directory = try TemporaryDirectory()
        let repository = EncryptedFileRepository(fileURL: directory.url.appending(path: "none.store"), encryptor: encryptor)
        #expect(try await repository.load() == AppData())
    }

    @Test("Only the newest backups are kept")
    func backupRotation() async throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "gage.store")
        let repository = EncryptedFileRepository(fileURL: file, encryptor: encryptor, backupCount: 2)
        for index in 0..<5 {
            var data = AppData()
            data.profile.phone = "\(index)"
            try await repository.save(data)
        }
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.url.appending(path: "Backups").path(percentEncoded: false))
        #expect(backups.count == 2)
    }

    @Test("Data from a newer app version is not overwritten")
    func newerSchemaIsRejected() async throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "gage.store")
        var data = AppData()
        data.schemaVersion = AppData.currentSchemaVersion + 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encryptor.seal(encoder.encode(data)).write(to: file)

        let repository = EncryptedFileRepository(fileURL: file, encryptor: encryptor)
        await #expect(throws: PersistenceError.self) { try await repository.load() }
    }

    @Test("Archived PDFs cannot be overwritten and are verified")
    func archive() async throws {
        let directory = try TemporaryDirectory()
        let archive = FileInvoiceArchive(baseURL: directory.url, digest: SHA256Digest())
        let number = try #require(InvoiceNumber("2026-015"))
        let pdf = Data("%PDF-1.7 test".utf8)

        let document = try await archive.archive(pdf: pdf, number: number)
        #expect(document.url.lastPathComponent == "Rechnung_2026-015.pdf")
        #expect(document.url.deletingLastPathComponent().lastPathComponent == "2026")
        #expect(try await archive.verify(number: number, expectedSHA256: document.sha256))
        let matchesWrongDigest = try await archive.verify(number: number, expectedSHA256: String(repeating: "0", count: 64))
        #expect(!matchesWrongDigest)

        await #expect(throws: ArchiveError.alreadyArchived(number)) {
            try await archive.archive(pdf: Data("other".utf8), number: number)
        }
        #expect(throws: (any Error).self) { try Data("manipuliert".utf8).write(to: document.url) }
    }
}
