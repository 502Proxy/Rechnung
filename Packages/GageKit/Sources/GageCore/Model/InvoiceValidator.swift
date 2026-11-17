import Foundation

public enum InvoiceValidationError: Error, Hashable, Sendable, LocalizedError {
    case missingCustomer
    case noLineItems
    case emptyDescription(position: Int)
    case nonPositiveQuantity(position: Int)
    case negativePrice(position: Int)
    case nonPositiveTotal
    case totalExceedsLimit(Money)
    case invalidPaymentTerm
    case serviceDateTooFarFromIssueDate

    public var errorDescription: String? {
        switch self {
        case .missingCustomer: "Bitte wähle einen Kunden aus."
        case .noLineItems: "Die Rechnung braucht mindestens eine Position."
        case let .emptyDescription(position): "Position \(position): Beschreibung fehlt."
        case let .nonPositiveQuantity(position): "Position \(position): Menge muss größer als 0 sein."
        case let .negativePrice(position): "Position \(position): Preis darf nicht negativ sein."
        case .nonPositiveTotal: "Der Rechnungsbetrag muss größer als 0 € sein."
        case let .totalExceedsLimit(limit): "Der Rechnungsbetrag übersteigt die Plausibilitätsgrenze von \(limit.formatted())."
        case .invalidPaymentTerm: "Das Zahlungsziel muss zwischen 0 und 90 Tagen liegen."
        case .serviceDateTooFarFromIssueDate: "Leistungs- und Rechnungsdatum liegen mehr als ein Jahr auseinander."
        }
    }
}

/// Checks a draft before it can be saved. Every rule returns a message the user can act on.
public struct InvoiceValidator: Sendable {
    /// Guards against typos such as an extra zero. A single invoice above this is implausible for a small business.
    public static let maximumTotal = Money(cents: 5_000_000)
    public static let maximumDescriptionLength = 500

    public init() {}

    public func validate(_ draft: InvoiceDraft) -> [InvoiceValidationError] {
        var errors: [InvoiceValidationError] = []
        if draft.customerID == nil { errors.append(.missingCustomer) }
        if draft.lineItems.isEmpty { errors.append(.noLineItems) }

        for (index, item) in draft.lineItems.enumerated() {
            let position = index + 1
            let description = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if description.isEmpty || description.count > Self.maximumDescriptionLength {
                errors.append(.emptyDescription(position: position))
            }
            if item.quantity <= 0 { errors.append(.nonPositiveQuantity(position: position)) }
            if item.unitPrice.isNegative { errors.append(.negativePrice(position: position)) }
        }

        if !draft.lineItems.isEmpty, !draft.total.isPositive { errors.append(.nonPositiveTotal) }
        if draft.total > Self.maximumTotal { errors.append(.totalExceedsLimit(Self.maximumTotal)) }
        if !(0...90).contains(draft.paymentTermDays) { errors.append(.invalidPaymentTerm) }
        if abs(draft.serviceDate.days(until: draft.issueDate)) > 366 { errors.append(.serviceDateTooFarFromIssueDate) }
        return errors
    }
}
