import Foundation
import GageCore
import OSLog

public enum ArchiveError: Error, Equatable, Sendable, LocalizedError {
    case alreadyArchived(InvoiceNumber)
    case missing(InvoiceNumber)

    public var errorDescription: String? {
        switch self {
        case let .alreadyArchived(number): "Rechnung \(number) liegt bereits im Archiv und wird nicht überschrieben."
        case let .missing(number): "Die PDF-Datei zu Rechnung \(number) fehlt im Archiv."
        }
    }
}

/// Archives issued invoices as PDFs at `<base>/<year>/Rechnung_<number>.pdf`.
///
/// Archived files are never overwritten. They are made read-only and get the
/// "locked" flag in Finder. Their SHA-256 is stored with the invoice, so any
/// later change can be detected (GoBD: Unveränderbarkeit, Nachvollziehbarkeit).
public actor FileInvoiceArchive: InvoiceArchive {
    private let baseURL: URL
    private let digest: any DigestProviding
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "app.gage", category: "archive")

    public init(baseURL: URL, digest: any DigestProviding) {
        self.baseURL = baseURL
        self.digest = digest
    }

    public func location(of number: InvoiceNumber) -> URL {
        baseURL
            .appending(path: number.year.map(String.init) ?? "Sonstige", directoryHint: .isDirectory)
            .appending(path: "Rechnung_\(number).pdf")
    }

    public func archive(pdf: Data, number: InvoiceNumber) async throws -> ArchivedDocument {
        let url = location(of: number)
        guard !fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ArchiveError.alreadyArchived(number)
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try pdf.write(to: url, options: [.withoutOverwriting])
        try fileManager.setAttributes([.posixPermissions: 0o400, .immutable: true], ofItemAtPath: url.path(percentEncoded: false))
        logger.info("Archived invoice \(number.description, privacy: .private)")
        return ArchivedDocument(url: url, sha256: digest.sha256Hex(of: pdf))
    }

    public func existingDocument(for number: InvoiceNumber) async throws -> ArchivedDocument? {
        let url = location(of: number)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try ArchivedDocument(url: url, sha256: digest.sha256Hex(of: Data(contentsOf: url)))
    }

    public func verify(number: InvoiceNumber, expectedSHA256: String) async throws -> Bool {
        let url = location(of: number)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { throw ArchiveError.missing(number) }
        return try digest.sha256Hex(of: Data(contentsOf: url)) == expectedSHA256
    }
}
