import Foundation
@testable import GageCore
import Testing

@Suite("Bookkeeping workflow")
struct WorkflowTests {
    private let workflow = BookkeepingWorkflow(digest: TestDigest())
    private let now = Fixtures.instant("2026-11-17", hour: 10)

    private func issuedInvoice(in data: inout AppData, customer: Customer = Fixtures.kantine, amount: Int64 = 70000) throws -> Invoice {
        let invoice = try workflow.createInvoice(from: Fixtures.draft(customer: customer, amount: amount), in: &data, now: now)
        try workflow.issueInvoice(
            id: invoice.id,
            archived: ArchivedDocument(url: URL(fileURLWithPath: "/tmp/x.pdf"), sha256: "digest"),
            in: &data,
            today: Fixtures.date("2026-11-02"),
            now: now
        )
        return try #require(data.invoice(withID: invoice.id))
    }

    @Test("Numbers are assigned sequentially")
    func sequentialNumbers() throws {
        var data = Fixtures.appData()
        let first = try workflow.createInvoice(from: Fixtures.draft(), in: &data, now: now)
        let second = try workflow.createInvoice(from: Fixtures.draft(), in: &data, now: now)
        #expect(first.number.description == "2026-001")
        #expect(second.number.description == "2026-002")
    }

    @Test("Issuing requires a complete sender profile")
    func incompleteProfile() throws {
        var data = Fixtures.appData()
        data.profile.taxNumber = ""
        let invoice = try workflow.createInvoice(from: Fixtures.draft(), in: &data, now: now)
        #expect(throws: BookkeepingWorkflow.WorkflowError.incompleteProfile(["Steuernummer"])) {
            try workflow.issueInvoice(
                id: invoice.id,
                archived: ArchivedDocument(url: URL(fileURLWithPath: "/tmp/x.pdf"), sha256: "d"),
                in: &data,
                today: Fixtures.date("2026-11-02"),
                now: now
            )
        }
    }

    @Test("An exact payment marks the invoice as paid")
    func exactPaymentIsBookedAutomatically() throws {
        var data = Fixtures.appData()
        let invoice = try issuedInvoice(in: &data)
        let payment = BankTransaction(
            id: "p1",
            bookingDate: Fixtures.date("2026-11-10"),
            amount: Money(cents: 70000),
            counterpartyName: "Club Kantine GmbH",
            reference: "RE \(invoice.number) danke"
        )
        let summary = workflow.importTransactions([payment, payment], in: &data, now: now)
        #expect(summary.imported == 1)
        #expect(summary.autoMatched == [invoice.number])
        #expect(data.invoice(withID: invoice.id)?.paidOn == Fixtures.date("2026-11-10"))
        #expect(data.transactions.count == 1)
    }

    @Test("A payment without the number only becomes a suggestion")
    func ambiguousPaymentNeedsReview() throws {
        var data = Fixtures.appData()
        let invoice = try issuedInvoice(in: &data)
        let payment = BankTransaction(
            id: "p2",
            bookingDate: Fixtures.date("2026-11-17"),
            amount: Money(cents: 70000),
            counterpartyName: "Club Kantine GmbH",
            reference: "Gage November danke!"
        )
        let summary = workflow.importTransactions([payment], in: &data, now: now)
        #expect(summary.needsReview == 1)
        #expect(data.invoice(withID: invoice.id)?.paidOn == nil)
        #expect(workflow.suggestion(for: "p2", in: data) == .suggested(invoiceID: invoice.id, reason: .amountAndPayerMatch))

        try workflow.confirmPayment(transactionID: "p2", invoiceID: invoice.id, in: &data, now: now)
        #expect(data.invoice(withID: invoice.id)?.paidOn == Fixtures.date("2026-11-17"))
    }

    @Test("Every change extends a verifiable audit trail")
    func auditTrail() throws {
        var data = Fixtures.appData()
        _ = try issuedInvoice(in: &data)
        #expect(data.auditTrail.map(\.action) == [.invoiceCreated, .invoiceIssued])
        #expect(AuditTrail.firstViolation(in: data.auditTrail, digest: TestDigest()) == nil)

        let roundTripped = try JSONDecoder().decode([AuditEntry].self, from: JSONEncoder().encode(data.auditTrail))
        #expect(AuditTrail.firstViolation(in: roundTripped, digest: TestDigest()) == nil)

        var tampered = data.auditTrail
        let original = tampered[0]
        tampered[0] = AuditEntry(
            timestamp: original.timestamp,
            action: original.action,
            subject: "2026-999",
            previousHash: original.previousHash,
            hash: original.hash
        )
        #expect(AuditTrail.firstViolation(in: tampered, digest: TestDigest()) == 0)
    }

    @Test("The calendar automation creates one draft per gig")
    func autoInvoicing() {
        var data = Fixtures.appData()
        let planner = GigInvoicePlanner(timeZone: Fixtures.berlin)
        let gig = Gig(
            id: "evt-1",
            title: "Clubnacht",
            start: Fixtures.instant("2026-11-15", hour: 23),
            location: "Club Kantine, Hamburg",
            fee: Money(cents: 70000),
            customerName: "Kantine"
        )
        let unknown = Gig(id: "evt-2", title: "Privatfeier", start: gig.start, location: nil, fee: Money(cents: 500), customerName: "Unbekannt")

        let first = workflow.runAutoInvoicing(gigs: [gig, unknown], in: &data, planner: planner, now: now)
        #expect(first.created.count == 1)
        #expect(first.created.first?.source == .gig(eventID: "evt-1"))
        #expect(first.created.first?.serviceDate == Fixtures.date("2026-11-15"))
        #expect(first.unresolved.map(\.id) == ["evt-2"])

        let second = workflow.runAutoInvoicing(gigs: [gig], in: &data, planner: planner, now: now)
        #expect(second.created.isEmpty)
    }
}
