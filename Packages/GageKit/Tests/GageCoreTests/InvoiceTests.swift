import Foundation
@testable import GageCore
import Testing

@Suite("Invoice lifecycle")
struct InvoiceTests {
    private let number = InvoiceNumber(year: 2026, sequence: 14)!

    @Test("Validation names every problem")
    func validation() {
        var draft = Fixtures.draft()
        draft.customerID = nil
        draft.lineItems = [LineItem(description: " ", quantity: 0, unitPrice: Money(cents: -100))]
        draft.paymentTermDays = 120
        let errors = InvoiceValidator().validate(draft)
        #expect(errors.contains(.missingCustomer))
        #expect(errors.contains(.emptyDescription(position: 1)))
        #expect(errors.contains(.nonPositiveQuantity(position: 1)))
        #expect(errors.contains(.negativePrice(position: 1)))
        #expect(errors.contains(.invalidPaymentTerm))
        #expect(throws: InvoiceError.self) { try Invoice(number: number, draft: draft) }
    }

    @Test("Implausibly high totals are rejected")
    func plausibilityLimit() {
        let draft = Fixtures.draft(amount: 9_000_000)
        #expect(InvoiceValidator().validate(draft).contains(.totalExceedsLimit(InvoiceValidator.maximumTotal)))
    }

    @Test("Issued invoices are locked")
    func issuedInvoicesAreImmutable() throws {
        var invoice = try Invoice(number: number, draft: Fixtures.draft())
        #expect(invoice.isDraft)
        try invoice.issue(on: Fixtures.date("2026-11-02"), archiveDigest: "abc")
        #expect(invoice.archiveDigest == "abc")
        #expect(throws: InvoiceError.notEditable) { try invoice.update(with: Fixtures.draft(amount: 1)) }
        #expect(throws: InvoiceError.alreadyIssued) { try invoice.issue(on: Fixtures.date("2026-11-03"), archiveDigest: "x") }
    }

    @Test("State follows the due date")
    func derivedState() throws {
        var invoice = try Invoice(number: number, draft: Fixtures.draft())
        #expect(invoice.state(asOf: Fixtures.date("2026-11-20")) == .draft)
        try invoice.issue(on: Fixtures.date("2026-11-02"), archiveDigest: "abc")
        #expect(invoice.dueDate == Fixtures.date("2026-11-16"))
        #expect(invoice.state(asOf: Fixtures.date("2026-11-16")) == .open)
        #expect(invoice.state(asOf: Fixtures.date("2026-11-17")) == .overdue)
        try invoice.markPaid(on: Fixtures.date("2026-11-17"))
        #expect(invoice.state(asOf: Fixtures.date("2026-11-17")) == .paid)
        #expect(throws: InvoiceError.alreadyPaid) { try invoice.markPaid(on: Fixtures.date("2026-11-18")) }
    }

    @Test("Drafts cannot be marked as paid")
    func draftCannotBePaid() throws {
        var invoice = try Invoice(number: number, draft: Fixtures.draft())
        #expect(throws: InvoiceError.notIssued) { try invoice.markPaid(on: Fixtures.date("2026-11-17")) }
    }

    @Test("Totals are summed from the line items")
    func totals() throws {
        var draft = Fixtures.draft()
        draft.lineItems.append(LineItem(description: "Anfahrt", quantity: Decimal(string: "120")!, unit: .kilometer, unitPrice: Money(cents: 30)))
        let invoice = try Invoice(number: number, draft: draft)
        #expect(invoice.total == Money(cents: 73600))
    }
}
