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

    static func transaction(from payment: BunqPayment, accountIBAN: String, timeZone: TimeZone = .current) -> BankTransaction? {
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
            reference: payment.description,
            accountIBAN: accountIBAN
        )
    }
}

/// Connects to bunq and provides the payments of one selected account as `BankTransaction`s.
public struct BunqConnection: BankConnecting {
    private let client: BunqClient

    public init(client: BunqClient) {
        self.client = client
    }

    public func connect(apiKey: String) async throws {
        try await client.connect(apiKey: apiKey)
    }

    public func disconnect() async throws {
        try await client.disconnect()
    }

    public func accounts() async throws -> [BankAccount] {
        try await client.accounts().compactMap { account in
            guard let iban = account.iban else { return nil }
            let name = account.description?.trimmingCharacters(in: .whitespaces) ?? ""
            return BankAccount(iban: iban, name: name.isEmpty ? "bunq-Konto" : name)
        }
    }

    public func transactions(since date: LocalDate, accountIBAN: String) async throws -> [BankTransaction] {
        let wanted = BookkeepingWorkflow.normalizedIBAN(accountIBAN)
        let accounts = try await client.accounts()
        guard let account = accounts.first(where: { $0.iban.map(BookkeepingWorkflow.normalizedIBAN) == wanted }) else {
            throw BunqError.accountNotFound
        }
        return try await client.payments(accountID: account.id, since: date)
            .compactMap { BunqMapping.transaction(from: $0, accountIBAN: wanted) }
    }
}
