import Foundation

/// The app's use cases as pure functions over `AppData`.
///
/// No I/O happens here. The caller loads, runs a step and saves. That keeps
/// every business rule testable in isolation, and each change is recorded in
/// the audit trail.
public struct BookkeepingWorkflow: Sendable {
    public enum WorkflowError: Error, Equatable, Sendable, LocalizedError {
        case unknownInvoice
        case unknownCustomer
        case unknownTransaction
        case numberRangeExhausted
        case incompleteProfile([String])

        public var errorDescription: String? {
            switch self {
            case .unknownInvoice: "Die Rechnung wurde nicht gefunden."
            case .unknownCustomer: "Der Kunde wurde nicht gefunden."
            case .unknownTransaction: "Die Buchung wurde nicht gefunden."
            case .numberRangeExhausted: "Für dieses Jahr ist keine Rechnungsnummer mehr frei."
            case let .incompleteProfile(fields):
                "Bitte ergänze in den Einstellungen: \(fields.joined(separator: ", "))."
            }
        }
    }

    public struct BankImportSummary: Hashable, Sendable {
        public var imported = 0
        public var autoMatched: [InvoiceNumber] = []
        public var needsReview = 0

        public init() {}
    }

    private let digest: any DigestProviding
    private let matcher = PaymentMatcher()

    public init(digest: any DigestProviding) {
        self.digest = digest
    }

    // MARK: Invoices

    @discardableResult
    public func createInvoice(
        from draft: InvoiceDraft,
        source: InvoiceSource = .manual,
        in data: inout AppData,
        now: Date
    ) throws -> Invoice {
        guard let customerID = draft.customerID, data.customer(withID: customerID) != nil else {
            throw WorkflowError.unknownCustomer
        }
        guard let number = InvoiceNumber.next(after: data.invoices.map(\.number), year: draft.issueDate.year) else {
            throw WorkflowError.numberRangeExhausted
        }
        let invoice = try Invoice(number: number, draft: draft, source: source)
        data.invoices.append(invoice)
        record(.invoiceCreated, subject: number.description, in: &data, now: now)
        return invoice
    }

    public func updateInvoice(id: UUID, with draft: InvoiceDraft, in data: inout AppData, now: Date) throws {
        guard let index = data.invoices.firstIndex(where: { $0.id == id }) else { throw WorkflowError.unknownInvoice }
        try data.invoices[index].update(with: draft)
        record(.invoiceUpdated, subject: data.invoices[index].number.description, in: &data, now: now)
    }

    /// Locks the invoice once its PDF has been archived.
    public func issueInvoice(id: UUID, archived: ArchivedDocument, in data: inout AppData, today: LocalDate, now: Date) throws {
        let missing = data.profile.missingMandatoryFields
        guard missing.isEmpty else { throw WorkflowError.incompleteProfile(missing) }
        guard let index = data.invoices.firstIndex(where: { $0.id == id }) else { throw WorkflowError.unknownInvoice }
        try data.invoices[index].issue(on: today, archiveDigest: archived.sha256)
        record(.invoiceIssued, subject: "\(data.invoices[index].number) sha256=\(archived.sha256)", in: &data, now: now)
    }

    public func markInvoicePaid(id: UUID, on date: LocalDate, in data: inout AppData, now: Date) throws {
        guard let index = data.invoices.firstIndex(where: { $0.id == id }) else { throw WorkflowError.unknownInvoice }
        try data.invoices[index].markPaid(on: date)
        record(.invoicePaid, subject: data.invoices[index].number.description, in: &data, now: now)
    }

    // MARK: Customers & profile

    public func saveCustomer(_ customer: Customer, in data: inout AppData, now: Date) {
        if let index = data.customers.firstIndex(where: { $0.id == customer.id }) {
            data.customers[index] = customer
        } else {
            data.customers.append(customer)
        }
        record(.customerSaved, subject: customer.id.uuidString, in: &data, now: now)
    }

    public func updateProfile(_ profile: BusinessProfile, in data: inout AppData, now: Date) {
        data.profile = profile
        record(.profileUpdated, subject: "profile", in: &data, now: now)
    }

    // MARK: Bank

    /// Adds new bookings, skips ones already imported and books unambiguous payments right away.
    @discardableResult
    public func importTransactions(
        _ incoming: [BankTransaction],
        in data: inout AppData,
        now: Date
    ) -> BankImportSummary {
        var summary = BankImportSummary()
        var known = Set(data.transactions.map(\.id))

        for var transaction in incoming where !known.contains(transaction.id) {
            known.insert(transaction.id)
            summary.imported += 1
            let openInvoices = data.invoices.filter { $0.issuedOn != nil && $0.paidOn == nil }
            if case let .exact(invoiceID) = matcher.match(transaction, openInvoices: openInvoices, customers: data.customers),
               let index = data.invoices.firstIndex(where: { $0.id == invoiceID }),
               (try? data.invoices[index].markPaid(on: transaction.bookingDate)) != nil {
                transaction.classification = .invoicePayment(invoiceID: invoiceID)
                summary.autoMatched.append(data.invoices[index].number)
                record(.paymentMatched, subject: "\(transaction.id) -> \(data.invoices[index].number)", in: &data, now: now)
            } else {
                summary.needsReview += 1
            }
            data.transactions.append(transaction)
        }
        return summary
    }

    public func suggestion(for transactionID: String, in data: AppData) -> PaymentMatch {
        guard let transaction = data.transactions.first(where: { $0.id == transactionID }) else { return .none }
        let openInvoices = data.invoices.filter { $0.issuedOn != nil && $0.paidOn == nil }
        return matcher.match(transaction, openInvoices: openInvoices, customers: data.customers)
    }

    public func confirmPayment(transactionID: String, invoiceID: UUID, in data: inout AppData, now: Date) throws {
        guard let txIndex = data.transactions.firstIndex(where: { $0.id == transactionID }) else {
            throw WorkflowError.unknownTransaction
        }
        guard let invoiceIndex = data.invoices.firstIndex(where: { $0.id == invoiceID }) else {
            throw WorkflowError.unknownInvoice
        }
        try data.invoices[invoiceIndex].markPaid(on: data.transactions[txIndex].bookingDate)
        data.transactions[txIndex].classification = .invoicePayment(invoiceID: invoiceID)
        record(.paymentMatched, subject: "\(transactionID) -> \(data.invoices[invoiceIndex].number)", in: &data, now: now)
    }

    public func classify(
        transactionID: String,
        as classification: TransactionClassification,
        in data: inout AppData,
        now: Date
    ) throws {
        guard let index = data.transactions.firstIndex(where: { $0.id == transactionID }) else {
            throw WorkflowError.unknownTransaction
        }
        data.transactions[index].classification = classification
        record(.transactionClassified, subject: transactionID, in: &data, now: now)
    }

    // MARK: Calendar

    /// Creates drafts for all gigs that are due. Gigs without a clearly
    /// matching customer are skipped and returned, so the UI can point them out.
    public func runAutoInvoicing(
        gigs: [Gig],
        in data: inout AppData,
        planner: GigInvoicePlanner,
        now: Date
    ) -> (created: [Invoice], unresolved: [Gig]) {
        let rule = data.settings.autoInvoice
        var created: [Invoice] = []
        var unresolved: [Gig] = []
        let today = LocalDate(now, calendar: Self.calendar(in: planner.timeZone))

        for gig in planner.gigsDue(gigs, invoices: data.invoices, rule: rule, now: now) {
            guard let customer = planner.resolveCustomer(for: gig, in: data.customers) else {
                unresolved.append(gig)
                continue
            }
            let draft = planner.makeDraft(
                for: gig,
                customer: customer,
                issueDate: today,
                paymentTermDays: data.settings.defaultPaymentTermDays
            )
            if let invoice = try? createInvoice(from: draft, source: .gig(eventID: gig.id), in: &data, now: now) {
                created.append(invoice)
            } else {
                unresolved.append(gig)
            }
        }
        return (created, unresolved)
    }

    // MARK: Private

    private func record(_ action: AuditEntry.Action, subject: String, in data: inout AppData, now: Date) {
        data.auditTrail = AuditTrail.appending(action, subject: subject, to: data.auditTrail, at: now, digest: digest)
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
