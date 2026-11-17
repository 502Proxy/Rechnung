import AppKit
import Foundation
import GageCore
import GageIntegrations
import Observation
import OSLog

/// The UI's central state. Delegates every business rule to `BookkeepingWorkflow`
/// and only coordinates loading, saving and integrations.
@MainActor
@Observable
public final class AppModel {
    public private(set) var data = AppData()
    public private(set) var isLoaded = false
    public private(set) var gigs: [Gig] = []
    public private(set) var unresolvedGigs: [Gig] = []
    public private(set) var isSyncingBank = false
    public private(set) var isSyncingCalendar = false
    public private(set) var lastBankSync: Date?
    public private(set) var calendarTitles: [String] = []
    /// The configured calendar does not exist; the gigs view asks for a choice.
    public private(set) var calendarNeedsSelection = false
    public private(set) var bankAccounts: [BankAccount] = []
    public var errorMessage: String?
    public var infoMessage: String?

    let dependencies: AppDependencies
    private let workflow: BookkeepingWorkflow
    private let planner = GigInvoicePlanner()
    private let logger = Logger(subsystem: "app.gage", category: "app")

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        workflow = BookkeepingWorkflow(digest: dependencies.digest)
    }

    public var today: LocalDate { LocalDate(dependencies.now()) }

    // MARK: Loading

    public func load() async {
        do {
            data = try await dependencies.repository.load()
            isLoaded = true
            if AuditTrail.firstViolation(in: data.auditTrail, digest: dependencies.digest) != nil {
                errorMessage = "Das Änderungsprotokoll ist nicht mehr lückenlos. Die Daten wurden möglicherweise außerhalb von Gage verändert."
            }
        } catch {
            logger.error("Loading failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Deine Daten konnten nicht geladen werden: \(error.localizedDescription)"
        }
    }

    // MARK: Lookups

    public func customer(for invoice: Invoice) -> Customer? { data.customer(withID: invoice.customerID) }

    public func invoice(for gig: Gig) -> Invoice? {
        data.invoices.first { $0.source == .gig(eventID: gig.id) }
    }

    public var sortedInvoices: [Invoice] { data.invoices.sorted { $0.number > $1.number } }

    public func invoices(in state: InvoiceState?) -> [Invoice] {
        sortedInvoices.filter { state == nil || $0.state(asOf: today) == state }
    }

    public var transactionsNeedingReview: [BankTransaction] { data.transactions.filter(\.needsReview) }

    public func suggestion(for transaction: BankTransaction) -> PaymentMatch {
        workflow.suggestion(for: transaction.id, in: data)
    }

    public func report(year: Int) -> ProfitReport {
        ProfitReportCalculator().report(year: year, invoices: data.invoices, transactions: data.transactions)
    }

    public var smallBusinessStatus: SmallBusinessStatus {
        SmallBusinessMonitor().status(year: today.year, invoices: data.invoices)
    }

    public func plannedInvoiceDate(for gig: Gig) -> Date? {
        planner.isScheduled(gig, rule: data.settings.autoInvoice) ? planner.plannedCreationDate(for: gig, rule: data.settings.autoInvoice) : nil
    }

    public func resolvedCustomer(for gig: Gig) -> Customer? {
        planner.resolveCustomer(for: gig, in: data.customers)
    }

    // MARK: Invoices

    public func newDraft(for gig: Gig? = nil) -> InvoiceDraft {
        if let gig, let customer = resolvedCustomer(for: gig) {
            return planner.makeDraft(for: gig, customer: customer, issueDate: today, paymentTermDays: data.settings.defaultPaymentTermDays)
        }
        return InvoiceDraft(
            customerID: data.customers.first?.id,
            issueDate: today,
            serviceDate: today,
            paymentTermDays: data.settings.defaultPaymentTermDays,
            lineItems: [LineItem(description: "", unitPrice: .zero)]
        )
    }

    /// Saves a draft. Returns the stored invoice, or `nil` on error.
    @discardableResult
    public func saveDraft(_ draft: InvoiceDraft, editing id: UUID?, source: InvoiceSource = .manual) async -> Invoice? {
        var saved: Invoice?
        let succeeded = await commit { data in
            if let id {
                try workflow.updateInvoice(id: id, with: draft, in: &data, now: dependencies.now())
                saved = data.invoice(withID: id)
            } else {
                saved = try workflow.createInvoice(from: draft, source: source, in: &data, now: dependencies.now())
            }
        }
        return succeeded ? saved : nil
    }

    /// Archives the PDF, locks the invoice and opens a prepared e-mail.
    public func issueAndSend(_ id: UUID) async {
        guard let invoice = data.invoice(withID: id), let customer = customer(for: invoice) else { return }
        guard let recipient = customer.email else {
            errorMessage = "Für \(customer.name) ist keine E-Mail-Adresse hinterlegt."
            return
        }
        let missing = data.profile.missingMandatoryFields
        guard missing.isEmpty else {
            errorMessage = "Bitte ergänze zuerst in den Einstellungen: \(missing.joined(separator: ", "))."
            return
        }

        do {
            let document = try await archivedDocument(for: invoice, customer: customer)
            let issued = await commit { data in
                try workflow.issueInvoice(id: id, archived: document, in: &data, today: today, now: dependencies.now())
            }
            guard issued, let locked = data.invoice(withID: id) else { return }
            let mail = MailTemplates.invoice(locked, profile: data.profile)
            try dependencies.mailer.compose(OutgoingMail(recipient: recipient, subject: mail.subject, body: mail.body, attachment: document.url))
            infoMessage = "Rechnung \(locked.number) ist archiviert. Prüfe die E-Mail und sende sie ab."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func sendReminder(_ id: UUID) async {
        guard let invoice = data.invoice(withID: id), let recipient = customer(for: invoice)?.email else { return }
        do {
            let url = await dependencies.archive.location(of: invoice.number)
            let mail = MailTemplates.reminder(invoice, profile: data.profile)
            try dependencies.mailer.compose(OutgoingMail(recipient: recipient, subject: mail.subject, body: mail.body, attachment: url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func markPaid(_ id: UUID) async {
        await commit { data in try workflow.markInvoicePaid(id: id, on: today, in: &data, now: dependencies.now()) }
    }

    public func revealInFinder(_ id: UUID) async {
        guard let invoice = data.invoice(withID: id) else { return }
        let url = await dependencies.archive.location(of: invoice.number)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Checks whether the archived PDF is unchanged.
    public func verifyArchive(_ id: UUID) async {
        guard let invoice = data.invoice(withID: id), let digest = invoice.archiveDigest else { return }
        do {
            let intact = try await dependencies.archive.verify(number: invoice.number, expectedSHA256: digest)
            if intact {
                infoMessage = "Die archivierte PDF von \(invoice.number) ist unverändert."
            } else {
                errorMessage = "Die archivierte PDF von \(invoice.number) wurde verändert."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Customers & settings

    public func saveCustomer(_ customer: Customer) async {
        await commit { data in workflow.saveCustomer(customer, in: &data, now: dependencies.now()) }
    }

    public func saveProfile(_ profile: BusinessProfile) async {
        await commit { data in workflow.updateProfile(profile, in: &data, now: dependencies.now()) }
    }

    public func updateSettings(_ change: (inout AppSettings) -> Void) async {
        await commit { data in change(&data.settings) }
    }

    public func setAutoInvoice(_ enabled: Bool, for gig: Gig) async {
        await updateSettings { settings in
            if enabled {
                settings.autoInvoice.excludedEventIDs.remove(gig.id)
            } else {
                settings.autoInvoice.excludedEventIDs.insert(gig.id)
            }
        }
    }

    // MARK: Bank

    /// Connects bunq. Afterwards the user picks the account; with only one account it is selected automatically.
    public func connectBank(apiKey: String) async -> Bool {
        do {
            try await dependencies.bank.connect(apiKey: apiKey)
            await updateSettings {
                $0.bankConnectionEnabled = true
                $0.bankAccountIBAN = nil
            }
            await loadBankAccounts()
            if bankAccounts.count == 1, let only = bankAccounts.first {
                await selectBankAccount(only)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func disconnectBank() async {
        do {
            try await dependencies.bank.disconnect()
            await updateSettings {
                $0.bankConnectionEnabled = false
                $0.bankAccountIBAN = nil
            }
            bankAccounts = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadBankAccounts() async {
        guard data.settings.bankConnectionEnabled else { return }
        do {
            bankAccounts = try await dependencies.bank.accounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reads only this account from now on. Bookings of other accounts are removed from Gage.
    public func selectBankAccount(_ account: BankAccount) async {
        var removed = 0
        await commit { data in removed = workflow.selectBankAccount(iban: account.iban, in: &data, now: dependencies.now()) }
        if removed > 0 {
            infoMessage = "\(removed) Buchung(en) anderer Konten wurden aus Gage entfernt."
        }
        await syncBank()
    }

    public var selectedBankAccount: BankAccount? {
        guard let iban = data.settings.bankAccountIBAN else { return nil }
        return bankAccounts.first { BookkeepingWorkflow.normalizedIBAN($0.iban) == iban }
            ?? BankAccount(iban: iban, name: "Ausgewähltes Konto")
    }

    public func syncBank() async {
        guard data.settings.bankConnectionEnabled, let accountIBAN = data.settings.bankAccountIBAN, !isSyncingBank else { return }
        isSyncingBank = true
        defer { isSyncingBank = false }
        do {
            let since = data.transactions.map(\.bookingDate).max()?.adding(days: -7) ?? today.adding(days: -90)
            let incoming = try await dependencies.bank.transactions(since: since, accountIBAN: accountIBAN)
            var summary = BookkeepingWorkflow.BankImportSummary()
            await commit { data in summary = workflow.importTransactions(incoming, in: &data, now: dependencies.now()) }
            lastBankSync = dependencies.now()
            if !summary.autoMatched.isEmpty {
                infoMessage = "Als bezahlt verbucht: \(summary.autoMatched.map(\.description).joined(separator: ", "))"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func confirmSuggestion(for transaction: BankTransaction) async {
        guard let invoiceID = suggestion(for: transaction).invoiceID else { return }
        await commit { data in
            try workflow.confirmPayment(transactionID: transaction.id, invoiceID: invoiceID, in: &data, now: dependencies.now())
        }
    }

    public func classify(_ transaction: BankTransaction, as classification: TransactionClassification) async {
        await commit { data in
            try workflow.classify(transactionID: transaction.id, as: classification, in: &data, now: dependencies.now())
        }
    }

    // MARK: Calendar

    public func loadCalendarTitles() async {
        do {
            calendarTitles = try await dependencies.gigSource.calendarTitles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectCalendar(_ title: String) async {
        await updateSettings { $0.autoInvoice.calendarTitle = title }
        calendarNeedsSelection = false
        await syncCalendar()
    }

    /// Reads the gig calendar and creates drafts for gigs that are due.
    public func syncCalendar() async {
        let rule = data.settings.autoInvoice
        guard !isSyncingCalendar else { return }
        isSyncingCalendar = true
        defer { isSyncingCalendar = false }

        let now = dependencies.now()
        let interval = DateInterval(start: now.addingTimeInterval(-30 * 86400), end: now.addingTimeInterval(90 * 86400))
        do {
            gigs = try await dependencies.gigSource.gigs(in: interval, calendarTitle: rule.calendarTitle)
            calendarNeedsSelection = false
        } catch CalendarAccessError.calendarNotFound(_) {
            // Not an error dialog every 15 minutes: the gigs view asks for the calendar instead.
            gigs = []
            calendarNeedsSelection = true
            await loadCalendarTitles()
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        var created: [Invoice] = []
        await commit { data in
            let result = workflow.runAutoInvoicing(gigs: gigs, in: &data, planner: planner, now: now)
            created = result.created
            unresolvedGigs = result.unresolved
        }
        for invoice in created {
            await dependencies.notifier.notify(
                title: "Rechnung \(invoice.number) ist bereit",
                body: "Gage hat eine Rechnung aus deinem Kalender erstellt. Bitte prüfe und sende sie."
            )
        }
    }

    // MARK: Private

    /// Applies a change, saves it and adopts it only if saving succeeds.
    @discardableResult
    private func commit(_ change: (inout AppData) throws -> Void) async -> Bool {
        var updated = data
        do {
            try change(&updated)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        do {
            try await dependencies.repository.save(updated)
            data = updated
            return true
        } catch {
            logger.error("Saving failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
            return false
        }
    }

    private func archivedDocument(for invoice: Invoice, customer: Customer) async throws -> ArchivedDocument {
        if let existing = try await dependencies.archive.existingDocument(for: invoice.number) {
            // An earlier send stopped after archiving. The archived PDF is the binding copy.
            return existing
        }
        let pdf = try InvoicePDFRenderer.render(
            InvoiceDocumentModel(invoice: invoice, customer: customer, profile: data.profile, isDraft: false)
        )
        return try await dependencies.archive.archive(pdf: pdf, number: invoice.number)
    }
}
