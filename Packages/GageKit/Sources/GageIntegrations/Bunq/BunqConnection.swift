import Foundation
import GageCore

enum BunqMapping {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        return formatter
    }()

    /// bunq timestamps are UTC. The booking date is the calendar day in the user's time zone.
    static func bookingDate(from created: String, timeZone: TimeZone = .current) -> LocalDate? {
        guard let instant = timestampFormatter.date(from: created) else {
            return LocalDate(isoString: String(created.prefix(10)))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return LocalDate(instant, calendar: calendar)
    }

    static func transaction(from payment: BunqPayment, timeZone: TimeZone = .current) -> BankTransaction? {
        guard payment.amount.currency == "EUR",
              let value = Decimal(string: payment.amount.value, locale: Locale(identifier: "en_US_POSIX")),
              let date = bookingDate(from: payment.created, timeZone: timeZone)
        else { return nil }
        return BankTransaction(
            id: "bunq-\(payment.id)",
            bookingDate: date,
            amount: Money(euros: value),
            counterpartyName: payment.counterpartyAlias?.displayName ?? "Unbekannt",
            counterpartyIBAN: payment.counterpartyAlias?.iban,
            reference: payment.description
        )
    }
}

/// Connects the business account at bunq and provides its payments as `BankTransaction`s.
public struct BunqConnection: BankConnecting {
    private let client: BunqClient
    private let accountIBAN: String?

    /// - Parameter accountIBAN: Account to read. If `nil`, the first active account is used.
    public init(client: BunqClient, accountIBAN: String?) {
        self.client = client
        self.accountIBAN = accountIBAN
    }

    public func connect(apiKey: String) async throws {
        try await client.connect(apiKey: apiKey)
    }

    public func disconnect() async throws {
        try await client.disconnect()
    }

    public func transactions(since date: LocalDate) async throws -> [BankTransaction] {
        let accounts = try await client.accounts()
        let wanted = accountIBAN.map { $0.filter { !$0.isWhitespace }.uppercased() }
        guard let account = accounts.first(where: { wanted == nil || $0.iban == wanted }) else {
            throw BunqError.unexpectedPayload("Kein passendes Konto")
        }
        return try await client.payments(accountID: account.id, since: date).compactMap { BunqMapping.transaction(from: $0) }
    }
}
