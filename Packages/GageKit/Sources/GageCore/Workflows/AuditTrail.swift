import Foundation

/// One entry in the tamper-evident change log.
///
/// Each entry includes the hash of the one before it. A later change to any
/// entry breaks the chain, and `AuditTrail.verify` detects that.
public struct AuditEntry: Hashable, Sendable, Codable {
    public enum Action: String, Hashable, Sendable, Codable {
        case invoiceCreated
        case invoiceUpdated
        case invoiceIssued
        case invoiceImported
        case invoicePaid
        case paymentMatched
        case transactionClassified
        case customerSaved
        case profileUpdated
        case bankConnected
        case bankDisconnected
        case bankAccountSelected
    }

    public let timestamp: Date
    public let action: Action
    public let subject: String
    public let previousHash: String
    public let hash: String

    var canonicalPayload: Data {
        let milliseconds = Int64((timestamp.timeIntervalSince1970 * 1000).rounded())
        return Data("\(milliseconds)|\(action.rawValue)|\(subject)|\(previousHash)".utf8)
    }
}

public enum AuditTrail {
    static let genesisHash = String(repeating: "0", count: 64)

    public static func appending(
        _ action: AuditEntry.Action,
        subject: String,
        to trail: [AuditEntry],
        at timestamp: Date,
        digest: any DigestProviding
    ) -> [AuditEntry] {
        // Millisecond precision so the stored entry hashes to the same value after encoding.
        let rounded = Date(timeIntervalSince1970: (timestamp.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        let previous = trail.last?.hash ?? genesisHash
        let unsigned = AuditEntry(timestamp: rounded, action: action, subject: subject, previousHash: previous, hash: "")
        let entry = AuditEntry(
            timestamp: rounded,
            action: action,
            subject: subject,
            previousHash: previous,
            hash: digest.sha256Hex(of: unsigned.canonicalPayload)
        )
        return trail + [entry]
    }

    /// Index of the first broken entry, or `nil` if the chain is intact.
    public static func firstViolation(in trail: [AuditEntry], digest: any DigestProviding) -> Int? {
        var previous = genesisHash
        for (index, entry) in trail.enumerated() {
            guard entry.previousHash == previous,
                  entry.hash == digest.sha256Hex(of: entry.canonicalPayload)
            else { return index }
            previous = entry.hash
        }
        return nil
    }
}
