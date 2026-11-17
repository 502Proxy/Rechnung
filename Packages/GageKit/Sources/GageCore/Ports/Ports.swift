import Foundation

// Interfaces to the outside world (ports). GageCore only declares them; the
// implementations live in GageSecurity, GagePersistence and GageIntegrations.
// That keeps the domain logic testable and free of frameworks.

/// Everything the app stores locally, as one encrypted snapshot.
public struct AppData: Hashable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var profile: BusinessProfile
    public var customers: [Customer]
    public var invoices: [Invoice]
    public var transactions: [BankTransaction]
    public var settings: AppSettings
    public var auditTrail: [AuditEntry]

    public init(
        profile: BusinessProfile = .empty,
        customers: [Customer] = [],
        invoices: [Invoice] = [],
        transactions: [BankTransaction] = [],
        settings: AppSettings = AppSettings(),
        auditTrail: [AuditEntry] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.profile = profile
        self.customers = customers
        self.invoices = invoices
        self.transactions = transactions
        self.settings = settings
        self.auditTrail = auditTrail
    }

    public func customer(withID id: UUID) -> Customer? {
        customers.first { $0.id == id }
    }

    public func invoice(withID id: UUID) -> Invoice? {
        invoices.first { $0.id == id }
    }
}

public struct AppSettings: Hashable, Sendable {
    public var autoInvoice: AutoInvoiceRule
    public var numberScheme: InvoiceNumberScheme
    public var defaultPaymentTermDays: Int
    public var appLockEnabled: Bool
    public var autoLockAfterMinutes: Int
    public var bankConnectionEnabled: Bool
    /// The account Gage reads. Other accounts (e.g. the private one) are never imported.
    public var bankAccountIBAN: String?

    public init(
        autoInvoice: AutoInvoiceRule = AutoInvoiceRule(),
        numberScheme: InvoiceNumberScheme = .invoiceDate,
        defaultPaymentTermDays: Int = 14,
        appLockEnabled: Bool = true,
        autoLockAfterMinutes: Int = 5,
        bankConnectionEnabled: Bool = false,
        bankAccountIBAN: String? = nil
    ) {
        self.autoInvoice = autoInvoice
        self.numberScheme = numberScheme
        self.defaultPaymentTermDays = defaultPaymentTermDays
        self.appLockEnabled = appLockEnabled
        self.autoLockAfterMinutes = autoLockAfterMinutes
        self.bankConnectionEnabled = bankConnectionEnabled
        self.bankAccountIBAN = bankAccountIBAN
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case autoInvoice, numberScheme, defaultPaymentTermDays, appLockEnabled
        case autoLockAfterMinutes, bankConnectionEnabled, bankAccountIBAN
    }

    /// Settings added in later versions fall back to their defaults, so older stores stay readable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        autoInvoice = try container.decodeIfPresent(AutoInvoiceRule.self, forKey: .autoInvoice) ?? defaults.autoInvoice
        numberScheme = try container.decodeIfPresent(InvoiceNumberScheme.self, forKey: .numberScheme) ?? defaults.numberScheme
        defaultPaymentTermDays = try container.decodeIfPresent(Int.self, forKey: .defaultPaymentTermDays)
            ?? defaults.defaultPaymentTermDays
        appLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? defaults.appLockEnabled
        autoLockAfterMinutes = try container.decodeIfPresent(Int.self, forKey: .autoLockAfterMinutes)
            ?? defaults.autoLockAfterMinutes
        bankConnectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .bankConnectionEnabled)
            ?? defaults.bankConnectionEnabled
        bankAccountIBAN = try container.decodeIfPresent(String.self, forKey: .bankAccountIBAN)
    }
}

public protocol AppDataRepository: Sendable {
    func load() async throws -> AppData
    func save(_ data: AppData) async throws
}

public protocol GigSource: Sendable {
    /// Events in the calendar named `calendarTitle` (case-insensitive).
    func gigs(in interval: DateInterval, calendarTitle: String) async throws -> [Gig]
    /// Names of all calendars on this Mac, for the selection in Settings.
    func calendarTitles() async throws -> [String]
}

/// A bank connection the user sets up and removes in the app.
public protocol BankConnecting: Sendable {
    func connect(apiKey: String) async throws
    func disconnect() async throws
    /// All own accounts the API key can see.
    func accounts() async throws -> [BankAccount]
    /// Bookings of exactly one account since `date`.
    func transactions(since date: LocalDate, accountIBAN: String) async throws -> [BankTransaction]
}

public struct ArchivedDocument: Hashable, Sendable {
    public let url: URL
    public let sha256: String

    public init(url: URL, sha256: String) {
        self.url = url
        self.sha256 = sha256
    }
}

public protocol InvoiceArchive: Sendable {
    /// Saves the PDF of an issued invoice so that it cannot be overwritten.
    func archive(pdf: Data, number: InvoiceNumber) async throws -> ArchivedDocument
    /// The document already in the archive, if any (e.g. after an interrupted send).
    func existingDocument(for number: InvoiceNumber) async throws -> ArchivedDocument?
    /// Checks that the archived PDF still matches the stored digest.
    func verify(number: InvoiceNumber, expectedSHA256: String) async throws -> Bool
    func location(of number: InvoiceNumber) async -> URL
}

public protocol DigestProviding: Sendable {
    func sha256Hex(of data: Data) -> String
}

public struct OutgoingMail: Hashable, Sendable {
    public let recipient: EmailAddress
    public let subject: String
    public let body: String
    public let attachment: URL

    public init(recipient: EmailAddress, subject: String, body: String, attachment: URL) {
        self.recipient = recipient
        self.subject = subject
        self.body = body
        self.attachment = attachment
    }
}

public protocol MailComposing: Sendable {
    /// Opens a prepared message. The user checks it and sends it from their own mail app.
    @MainActor func compose(_ mail: OutgoingMail) throws
}
