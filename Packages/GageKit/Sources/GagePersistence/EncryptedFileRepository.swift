import Foundation
import GageCore
import GageSecurity
import OSLog

public enum PersistenceError: Error, Equatable, Sendable, LocalizedError {
    case newerSchema(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case let .newerSchema(found, supported):
            "Die Daten stammen aus einer neueren Gage-Version (Schema \(found), unterstützt bis \(supported)). Bitte aktualisiere die App."
        }
    }
}

/// Stores `AppData` as one encrypted file in the app container.
///
/// - Writes are atomic: a crash never leaves a half-written file behind.
/// - File permissions are 0600 and the folder is 0700.
/// - Before each write the previous version is rotated into `Backups/`
///   (encrypted as well) and only the newest `backupCount` copies are kept.
/// - Data from a newer schema version is refused instead of being overwritten.
public actor EncryptedFileRepository: AppDataRepository {
    private let fileURL: URL
    private let encryptor: DataEncryptor
    private let backupCount: Int
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "app.gage", category: "persistence")

    public init(fileURL: URL, encryptor: DataEncryptor, backupCount: Int = 10) {
        self.fileURL = fileURL
        self.encryptor = encryptor
        self.backupCount = max(0, backupCount)
    }

    /// Default location inside the sandbox container: `~/Library/Containers/<id>/Data/Library/Application Support/Gage/`.
    public static func defaultFileURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appending(path: "Gage", directoryHint: .isDirectory).appending(path: "gage.store")
    }

    public func load() async throws -> AppData {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            logger.info("No store found, starting with empty data")
            return AppData()
        }
        let sealed = try Data(contentsOf: fileURL)
        let plaintext = try encryptor.open(sealed)
        let data = try Self.decoder.decode(AppData.self, from: plaintext)
        guard data.schemaVersion <= AppData.currentSchemaVersion else {
            throw PersistenceError.newerSchema(found: data.schemaVersion, supported: AppData.currentSchemaVersion)
        }
        return data
    }

    public func save(_ data: AppData) async throws {
        try prepareDirectory(fileURL.deletingLastPathComponent())
        let sealed = try encryptor.seal(Self.encoder.encode(data))
        try rotateBackup()
        try sealed.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path(percentEncoded: false))
        logger.debug("Store saved (\(sealed.count, privacy: .public) bytes)")
    }

    // MARK: - Private

    private var backupDirectory: URL {
        fileURL.deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory)
    }

    private func prepareDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func rotateBackup() throws {
        guard backupCount > 0, fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try prepareDirectory(backupDirectory)
        let stamp = Self.backupStampFormatter.string(from: .now)
        let target = backupDirectory.appending(path: "gage-\(stamp)-\(UUID().uuidString.prefix(8)).store")
        try fileManager.copyItem(at: fileURL, to: target)

        let backups = try fileManager
            .contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "store" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in backups.dropFirst(backupCount) {
            try fileManager.removeItem(at: stale)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    private static let backupStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS"
        return formatter
    }()
}
