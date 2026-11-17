import Foundation

/// An engagement read from the calendar.
public struct Gig: Identifiable, Hashable, Sendable {
    /// Stable calendar identifier (`EKEvent.calendarItemExternalIdentifier`).
    public let id: String
    public var title: String
    public var start: Date
    public var location: String?
    public var fee: Money?
    public var customerName: String?

    public init(id: String, title: String, start: Date, location: String?, fee: Money?, customerName: String?) {
        self.id = id
        self.title = title
        self.start = start
        self.location = location
        self.fee = fee
        self.customerName = customerName
    }
}

/// Reads fee and customer from an event's notes, one field per line:
///
///     Gage: 1.400 €
///     Kunde: Nordlicht Events GmbH
public enum GigNoteParser {
    public struct Result: Hashable, Sendable {
        public var fee: Money?
        public var customerName: String?
    }

    private static let feeKeys: Set<String> = ["gage", "honorar", "fee"]
    private static let customerKeys: Set<String> = ["kunde", "rechnung an", "customer", "auftraggeber"]
    private static let maximumNoteLength = 10_000

    public static func parse(_ notes: String?) -> Result {
        var result = Result()
        guard let notes else { return result }

        for line in notes.prefix(maximumNoteLength).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if feeKeys.contains(key), result.fee == nil, let fee = AmountParser.parse(value), fee.isPositive {
                result.fee = fee
            } else if customerKeys.contains(key), result.customerName == nil, !value.isEmpty {
                result.customerName = String(value.prefix(200))
            }
        }
        return result
    }
}

/// Settings for creating invoices from calendar events.
///
/// The automation only creates drafts. Sending always needs one click from the
/// user (see docs/adr/0004-mail-versand-ueber-apple-mail.md).
public struct AutoInvoiceRule: Hashable, Sendable, Codable {
    public var isEnabled: Bool
    public var calendarTitle: String
    public var hour: Int
    public var minute: Int
    /// Events the user has turned off one by one.
    public var excludedEventIDs: Set<String>

    public init(
        isEnabled: Bool = true,
        calendarTitle: String = "Gigs",
        hour: Int = 9,
        minute: Int = 0,
        excludedEventIDs: Set<String> = []
    ) {
        self.isEnabled = isEnabled
        self.calendarTitle = calendarTitle
        self.hour = hour
        self.minute = minute
        self.excludedEventIDs = excludedEventIDs
    }
}

/// Decides when an invoice is due for which gig and builds the matching draft.
public struct GigInvoicePlanner: Sendable {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    /// The day after the gig, at the time set in the rule.
    public func plannedCreationDate(for gig: Gig, rule: AutoInvoiceRule) -> Date? {
        localDate(of: gig).adding(days: 1).date(hour: rule.hour, minute: rule.minute, in: timeZone)
    }

    public func isScheduled(_ gig: Gig, rule: AutoInvoiceRule) -> Bool {
        rule.isEnabled && !rule.excludedEventIDs.contains(gig.id) && gig.fee != nil
    }

    /// Gigs that need an invoice now: the planned time has passed and none exists yet.
    public func gigsDue(_ gigs: [Gig], invoices: [Invoice], rule: AutoInvoiceRule, now: Date) -> [Gig] {
        let invoicedEventIDs = Set(invoices.compactMap { invoice -> String? in
            if case let .gig(eventID) = invoice.source { return eventID }
            return nil
        })
        return gigs.filter { gig in
            guard isScheduled(gig, rule: rule), !invoicedEventIDs.contains(gig.id),
                  let planned = plannedCreationDate(for: gig, rule: rule)
            else { return false }
            return planned <= now
        }
    }

    public func resolveCustomer(for gig: Gig, in customers: [Customer]) -> Customer? {
        let candidates = [gig.customerName, gig.title, gig.location].compactMap { $0 }
        for candidate in candidates {
            let matches = customers.filter { customer in
                ([customer.name] + customer.aliases).contains { PaymentMatcher.namesResemble($0, candidate) }
            }
            if matches.count == 1 { return matches.first }
        }
        return nil
    }

    public func makeDraft(for gig: Gig, customer: Customer, issueDate: LocalDate, paymentTermDays: Int) -> InvoiceDraft {
        let description = [gig.title, gig.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return InvoiceDraft(
            customerID: customer.id,
            issueDate: issueDate,
            serviceDate: localDate(of: gig),
            paymentTermDays: paymentTermDays,
            lineItems: [LineItem(description: description, unitPrice: gig.fee ?? .zero)]
        )
    }

    public func localDate(of gig: Gig) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return LocalDate(gig.start, calendar: calendar)
    }
}
