import Foundation

/// An invoice number, unique per business (§ 14 Abs. 4 Nr. 4 UStG).
///
/// The law requires uniqueness, not a gapless sequence, so date-based numbers
/// such as `101126` or `101126_2` are allowed. Imported invoices keep their
/// original number.
public struct InvoiceNumber: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let value: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The number becomes part of the archive file name, so only safe characters are allowed:
        // no path separators, no leading dot, no "..".
        guard (1...40).contains(trimmed.count),
              trimmed.first.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) == true,
              !trimmed.contains(".."),
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) })
        else { return nil }
        value = trimmed
    }

    public var description: String { value }

    /// The year encoded in the number (`JJJJ-NNN` or `TTMMJJ[_n]`), used for archive folders.
    public var year: Int? {
        if value.range(of: #"^\d{4}-\d+$"#, options: .regularExpression) != nil {
            return Int(value.prefix(4))
        }
        if value.range(of: #"^\d{6}(_\d+)?$"#, options: .regularExpression) != nil,
           let shortYear = Int(value.dropFirst(4).prefix(2)) {
            return 2000 + shortYear
        }
        return nil
    }

    public static func < (lhs: InvoiceNumber, rhs: InvoiceNumber) -> Bool {
        lhs.value.localizedStandardCompare(rhs.value) == .orderedAscending
    }
}

/// How new invoice numbers are formed.
public enum InvoiceNumberScheme: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    /// Invoice date as `TTMMJJ`. Further invoices on the same day get `_2`, `_3`, …
    case invoiceDate
    /// Year and running number: `2026-001`, `2026-002`, …
    case yearSequence

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .invoiceDate: "Rechnungsdatum (TTMMJJ, z. B. 101126, 101126_2)"
        case .yearSequence: "Jahr und laufende Nummer (z. B. 2026-001)"
        }
    }

    /// The next free number. `existing` must contain all numbers ever issued, including imported ones.
    public func next(issueDate: LocalDate, existing: some Sequence<InvoiceNumber>) -> InvoiceNumber? {
        let taken = Set(existing.map(\.value))
        switch self {
        case .invoiceDate:
            let base = String(format: "%02d%02d%02d", issueDate.day, issueDate.month, issueDate.year % 100)
            if !taken.contains(base) { return InvoiceNumber(base) }
            for suffix in 2...999 where !taken.contains("\(base)_\(suffix)") {
                return InvoiceNumber("\(base)_\(suffix)")
            }
            return nil
        case .yearSequence:
            let prefix = String(format: "%04d-", issueDate.year)
            let highest = taken
                .filter { $0.hasPrefix(prefix) }
                .compactMap { Int($0.dropFirst(prefix.count)) }
                .max() ?? 0
            return InvoiceNumber(prefix + String(format: "%03d", highest + 1))
        }
    }
}

extension InvoiceNumber: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = InvoiceNumber(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid invoice number")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public enum BillingUnit: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case flatRate
    case hour
    case piece
    case kilometer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .flatRate: "Pauschal"
        case .hour: "Std."
        case .piece: "Stück"
        case .kilometer: "km"
        }
    }
}

public struct LineItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var description: String
    public var quantity: Decimal
    public var unit: BillingUnit
    public var unitPrice: Money

    public init(
        id: UUID = UUID(),
        description: String,
        quantity: Decimal = 1,
        unit: BillingUnit = .flatRate,
        unitPrice: Money
    ) {
        self.id = id
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
    }

    public var total: Money { unitPrice.multiplied(by: quantity) }
}

/// The fields a user can change while an invoice is still a draft.
public struct InvoiceDraft: Hashable, Sendable {
    public var customerID: UUID?
    public var issueDate: LocalDate
    public var serviceDate: LocalDate
    public var paymentTermDays: Int
    public var lineItems: [LineItem]
    public var note: String

    public init(
        customerID: UUID?,
        issueDate: LocalDate,
        serviceDate: LocalDate,
        paymentTermDays: Int = 14,
        lineItems: [LineItem],
        note: String = ""
    ) {
        self.customerID = customerID
        self.issueDate = issueDate
        self.serviceDate = serviceDate
        self.paymentTermDays = paymentTermDays
        self.lineItems = lineItems
        self.note = note
    }

    public var total: Money { lineItems.map(\.total).sum() }
    public var dueDate: LocalDate { issueDate.adding(days: paymentTermDays) }
}

public enum InvoiceSource: Hashable, Sendable, Codable {
    case manual
    /// Created from a calendar event; `eventID` is the event's external identifier.
    case gig(eventID: String)
    /// An earlier invoice taken over from a PDF. The original file is archived unchanged.
    case imported(fileName: String)
}

public enum InvoiceStatus: Hashable, Sendable, Codable {
    case draft
    case issued(on: LocalDate)
    case paid(issuedOn: LocalDate, paidOn: LocalDate)
}

/// The state a user sees, derived from the stored status and today's date.
public enum InvoiceState: String, Hashable, Sendable, CaseIterable {
    case draft
    case open
    case overdue
    case paid

    public var displayName: String {
        switch self {
        case .draft: "Entwurf"
        case .open: "Gesendet"
        case .overdue: "Überfällig"
        case .paid: "Bezahlt"
        }
    }
}

public enum InvoiceError: Error, Equatable, Sendable, LocalizedError {
    case notEditable
    case notIssued
    case alreadyIssued
    case alreadyPaid
    case paymentBeforeIssue
    case invalid([InvoiceValidationError])

    public var errorDescription: String? {
        switch self {
        case .notEditable: "Versendete Rechnungen können nicht mehr geändert werden. Erstelle stattdessen eine Stornorechnung."
        case .notIssued: "Die Rechnung wurde noch nicht versendet."
        case .alreadyIssued: "Die Rechnung wurde bereits versendet."
        case .alreadyPaid: "Die Rechnung ist bereits als bezahlt markiert."
        case .paymentBeforeIssue: "Das Zahlungsdatum liegt vor dem Rechnungsdatum."
        case let .invalid(errors): errors.compactMap(\.errorDescription).joined(separator: "\n")
        }
    }
}

/// An invoice. Once issued it can no longer be edited (GoBD: Unveränderbarkeit);
/// only its payment status changes after that.
public struct Invoice: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public private(set) var number: InvoiceNumber
    public let source: InvoiceSource
    public private(set) var customerID: UUID
    public private(set) var issueDate: LocalDate
    public private(set) var serviceDate: LocalDate
    public private(set) var paymentTermDays: Int
    public private(set) var lineItems: [LineItem]
    public private(set) var note: String
    public private(set) var status: InvoiceStatus
    /// SHA-256 of the archived PDF, set when the invoice is issued.
    public private(set) var archiveDigest: String?

    public init(id: UUID = UUID(), number: InvoiceNumber, draft: InvoiceDraft, source: InvoiceSource = .manual) throws {
        let errors = InvoiceValidator().validate(draft)
        guard errors.isEmpty, let customerID = draft.customerID else { throw InvoiceError.invalid(errors) }
        self.id = id
        self.number = number
        self.source = source
        self.customerID = customerID
        issueDate = draft.issueDate
        serviceDate = draft.serviceDate
        paymentTermDays = draft.paymentTermDays
        lineItems = draft.lineItems
        note = draft.note
        status = .draft
        archiveDigest = nil
    }

    public var total: Money { lineItems.map(\.total).sum() }
    public var dueDate: LocalDate { issueDate.adding(days: paymentTermDays) }
    public var isDraft: Bool { status == .draft }

    public var paidOn: LocalDate? {
        if case let .paid(_, paidOn) = status { return paidOn }
        return nil
    }

    public var issuedOn: LocalDate? {
        switch status {
        case .draft: nil
        case let .issued(on): on
        case let .paid(issuedOn, _): issuedOn
        }
    }

    public var draft: InvoiceDraft {
        InvoiceDraft(
            customerID: customerID,
            issueDate: issueDate,
            serviceDate: serviceDate,
            paymentTermDays: paymentTermDays,
            lineItems: lineItems,
            note: note
        )
    }

    public func state(asOf today: LocalDate) -> InvoiceState {
        switch status {
        case .draft: .draft
        case .paid: .paid
        case .issued: today > dueDate ? .overdue : .open
        }
    }

    public mutating func update(with draft: InvoiceDraft) throws {
        guard isDraft else { throw InvoiceError.notEditable }
        let errors = InvoiceValidator().validate(draft)
        guard errors.isEmpty, let customerID = draft.customerID else { throw InvoiceError.invalid(errors) }
        self.customerID = customerID
        issueDate = draft.issueDate
        serviceDate = draft.serviceDate
        paymentTermDays = draft.paymentTermDays
        lineItems = draft.lineItems
        note = draft.note
    }

    /// Drafts follow their invoice date when the number is date-based.
    public mutating func renumber(_ newNumber: InvoiceNumber) throws {
        guard isDraft else { throw InvoiceError.notEditable }
        number = newNumber
    }

    /// Locks the invoice. Afterwards only the payment status can change.
    public mutating func issue(on date: LocalDate, archiveDigest: String) throws {
        guard isDraft else { throw InvoiceError.alreadyIssued }
        status = .issued(on: date)
        self.archiveDigest = archiveDigest
    }

    public mutating func markPaid(on date: LocalDate) throws {
        switch status {
        case .draft: throw InvoiceError.notIssued
        case .paid: throw InvoiceError.alreadyPaid
        case let .issued(issuedOn):
            guard date >= issueDate else { throw InvoiceError.paymentBeforeIssue }
            status = .paid(issuedOn: issuedOn, paidOn: date)
        }
    }
}
