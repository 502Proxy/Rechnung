import Foundation

/// Expense categories, grouped the way the Anlage EÜR asks for them.
public enum ExpenseCategory: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case equipment
    case software
    case musicAndMedia
    case travel
    case telecommunication
    case insurance
    case marketing
    case otherBusiness

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .equipment: "Equipment (GWG)"
        case .software: "Software & Lizenzen"
        case .musicAndMedia: "Musik & Medien"
        case .travel: "Reisekosten"
        case .telecommunication: "Telekommunikation"
        case .insurance: "Versicherungen"
        case .marketing: "Werbung & Website"
        case .otherBusiness: "Sonstige Betriebsausgaben"
        }
    }
}

public enum TransactionClassification: Hashable, Sendable, Codable {
    case unreviewed
    case invoicePayment(invoiceID: UUID)
    case otherBusinessIncome
    case businessExpense(ExpenseCategory)
    case privateTransaction
}

/// An own account at the bank, e.g. the main account or a sub-account for the DJ business.
public struct BankAccount: Hashable, Sendable, Identifiable {
    public let iban: String
    public let name: String

    public var id: String { iban }

    public init(iban: String, name: String) {
        self.iban = iban
        self.name = name
    }
}

/// A booking on the business account. `id` is the bank's own identifier, which prevents duplicate imports.
public struct BankTransaction: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let bookingDate: LocalDate
    /// Positive for incoming payments, negative for outgoing ones.
    public let amount: Money
    public let counterpartyName: String
    public let counterpartyIBAN: String?
    public let reference: String
    /// IBAN of the own account the booking belongs to. Older imports have none.
    public let accountIBAN: String?
    public var classification: TransactionClassification

    public init(
        id: String,
        bookingDate: LocalDate,
        amount: Money,
        counterpartyName: String,
        counterpartyIBAN: String? = nil,
        reference: String,
        accountIBAN: String? = nil,
        classification: TransactionClassification = .unreviewed
    ) {
        self.id = id
        self.bookingDate = bookingDate
        self.amount = amount
        self.counterpartyName = counterpartyName
        self.counterpartyIBAN = counterpartyIBAN
        self.reference = reference
        self.accountIBAN = accountIBAN
        self.classification = classification
    }

    public var isIncoming: Bool { amount.isPositive }
    public var needsReview: Bool { classification == .unreviewed }
}
