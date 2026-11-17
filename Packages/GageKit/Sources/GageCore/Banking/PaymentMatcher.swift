import Foundation

public enum PaymentMatch: Hashable, Sendable {
    /// The reference names exactly one open invoice and the amount fits to the cent. Applied automatically.
    case exact(invoiceID: UUID)
    /// A plausible candidate. The user has to confirm it.
    case suggested(invoiceID: UUID, reason: SuggestionReason)
    case none

    public enum SuggestionReason: Hashable, Sendable {
        case referenceMatchesAmountDiffers
        case amountAndPayerMatch
        case amountMatchesOnly
    }

    public var invoiceID: UUID? {
        switch self {
        case let .exact(id), let .suggested(id, _): id
        case .none: nil
        }
    }
}

/// Matches incoming payments to open invoices.
///
/// Only an unambiguous match (invoice number in the reference and the exact amount)
/// is applied without asking. Everything else becomes a suggestion, so no invoice
/// is ever marked as paid by mistake.
public struct PaymentMatcher: Sendable {
    public init() {}

    public func match(_ transaction: BankTransaction, openInvoices: [Invoice], customers: [Customer]) -> PaymentMatch {
        guard transaction.isIncoming else { return .none }

        let referenced = openInvoices.filter { Self.reference(transaction.reference, mentions: $0.number) }
        if referenced.count == 1, let invoice = referenced.first {
            return invoice.total == transaction.amount
                ? .exact(invoiceID: invoice.id)
                : .suggested(invoiceID: invoice.id, reason: .referenceMatchesAmountDiffers)
        }

        let sameAmount = openInvoices.filter { $0.total == transaction.amount }
        let samePayer = sameAmount.filter { invoice in
            guard let customer = customers.first(where: { $0.id == invoice.customerID }) else { return false }
            return ([customer.name] + customer.aliases).contains {
                Self.namesResemble($0, transaction.counterpartyName)
            }
        }
        if samePayer.count == 1, let invoice = samePayer.first {
            return .suggested(invoiceID: invoice.id, reason: .amountAndPayerMatch)
        }
        if sameAmount.count == 1, let invoice = sameAmount.first {
            return .suggested(invoiceID: invoice.id, reason: .amountMatchesOnly)
        }
        return .none
    }

    // MARK: - Helpers

    /// True if `reference` contains the number as "2026-015", "2026015", "2026/015" or "2026 015",
    /// and it is not part of a longer number.
    static func reference(_ reference: String, mentions number: InvoiceNumber) -> Bool {
        let sequence = String(format: "%03d", number.sequence)
        let candidates = ["-", "", "/", " "].map { "\(number.year)\($0)\(sequence)" }
        return candidates.contains { candidate in
            var searchRange = reference.startIndex..<reference.endIndex
            while let found = reference.range(of: candidate, options: .caseInsensitive, range: searchRange) {
                let before = found.lowerBound > reference.startIndex ? reference[reference.index(before: found.lowerBound)] : nil
                let after = found.upperBound < reference.endIndex ? reference[found.upperBound] : nil
                if !(before?.isNumber ?? false), !(after?.isNumber ?? false) { return true }
                searchRange = found.upperBound..<reference.endIndex
            }
            return false
        }
    }

    static func namesResemble(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left.contains(right) || right.contains(left) { return true }
        let leftTokens = Set(left.split(separator: " ").filter { $0.count >= 4 })
        let rightTokens = Set(right.split(separator: " ").filter { $0.count >= 4 })
        return !leftTokens.isDisjoint(with: rightTokens)
    }

    private static let legalFormSuffixes: Set<String> = ["gmbh", "ug", "ag", "kg", "ev", "e.v", "gbr", "ohg", "mbh", "co"]

    private static func normalized(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        let cleaned = folded.map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : " " }
        return String(cleaned)
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty && !legalFormSuffixes.contains($0) }
            .joined(separator: " ")
    }
}
