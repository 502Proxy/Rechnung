import Foundation
@testable import GageCore
import Testing

@Suite("Domain services")
struct DomainServiceTests {
    @Test("Invoice numbers are found in references, not inside longer numbers")
    func referenceMatching() throws {
        let number = try #require(InvoiceNumber("2026-015"))
        #expect(PaymentMatcher.reference("RE 2026-015", mentions: number))
        #expect(PaymentMatcher.reference("Rechnung 2026015 Herbstnacht", mentions: number))
        #expect(PaymentMatcher.reference("re 2026/015", mentions: number))
        #expect(!PaymentMatcher.reference("RE 2026-0150", mentions: number))
        #expect(!PaymentMatcher.reference("12026-015", mentions: number))
        #expect(!PaymentMatcher.reference("Gage November", mentions: number))
    }

    @Test("Payer names are compared without legal forms or case")
    func nameResemblance() {
        #expect(PaymentMatcher.namesResemble("Club Kantine", "CLUB KANTINE GMBH"))
        #expect(PaymentMatcher.namesResemble("Kulturzentrum Schlachthof e.V.", "Schlachthof Bremen"))
        #expect(!PaymentMatcher.namesResemble("Hotel Seeblick", "Club Kantine GmbH"))
    }

    @Test("A payment that does not fit is never assigned")
    func matcherRejectsOutgoing() throws {
        let invoice = try Invoice(number: #require(InvoiceNumber("2026-001")), draft: Fixtures.draft())
        let outgoing = BankTransaction(
            id: "x",
            bookingDate: Fixtures.date("2026-11-01"),
            amount: Money(cents: -70000),
            counterpartyName: "Club Kantine",
            reference: "RE 2026-001"
        )
        #expect(PaymentMatcher().match(outgoing, openInvoices: [invoice], customers: [Fixtures.kantine]) == .none)
    }

    @Test("Fee and customer are read from the event notes")
    func gigNotes() {
        let result = GigNoteParser.parse("""
        Ablauf: Einlass 18 Uhr
        Gage: 1.400 €
        Kunde: Jana & Tom Lehmann
        """)
        #expect(result.fee == Money(cents: 140_000))
        #expect(result.customerName == "Jana & Tom Lehmann")
        #expect(GigNoteParser.parse("Gage: -50").fee == nil)
        #expect(GigNoteParser.parse(nil) == GigNoteParser.Result())
    }

    @Test("The invoice is due the day after the gig at the set time")
    func plannerTiming() {
        let planner = GigInvoicePlanner(timeZone: Fixtures.berlin)
        let gig = Gig(
            id: "e",
            title: "Hochzeit",
            start: Fixtures.instant("2026-11-21", hour: 18),
            location: nil,
            fee: Money(cents: 1),
            customerName: nil
        )
        let rule = AutoInvoiceRule(hour: 9)
        #expect(planner.plannedCreationDate(for: gig, rule: rule) == Fixtures.instant("2026-11-22", hour: 9))
        #expect(planner.gigsDue([gig], invoices: [], rule: rule, now: Fixtures.instant("2026-11-22", hour: 8, minute: 59)).isEmpty)
        #expect(planner.gigsDue([gig], invoices: [], rule: rule, now: Fixtures.instant("2026-11-22", hour: 9)).count == 1)

        var excluded = rule
        excluded.excludedEventIDs = ["e"]
        #expect(planner.gigsDue([gig], invoices: [], rule: excluded, now: Fixtures.instant("2026-12-01", hour: 9)).isEmpty)
    }

    @Test("The EÜR counts income when the money arrives")
    func profitReport() throws {
        var paidLastYear = try Invoice(
            number: Fixtures.number("2025-020"),
            draft: Fixtures.draft(issued: "2025-12-20", service: "2025-12-19")
        )
        try paidLastYear.issue(on: Fixtures.date("2025-12-20"), archiveDigest: "a")
        try paidLastYear.markPaid(on: Fixtures.date("2026-01-05"))

        var open = try Invoice(number: #require(InvoiceNumber("2026-001")), draft: Fixtures.draft(amount: 50000))
        try open.issue(on: Fixtures.date("2026-11-02"), archiveDigest: "b")

        let transactions = [
            BankTransaction(id: "t1", bookingDate: Fixtures.date("2026-03-04"), amount: Money(cents: -54900),
                            counterpartyName: "Thomann", reference: "Controller", classification: .businessExpense(.equipment)),
            BankTransaction(id: "t2", bookingDate: Fixtures.date("2026-11-10"), amount: Money(cents: -2340),
                            counterpartyName: "REWE", reference: "Karte", classification: .privateTransaction),
            BankTransaction(id: "t3", bookingDate: Fixtures.date("2026-11-12"), amount: Money(cents: -3995),
                            counterpartyName: "Telekom", reference: "Mobilfunk"),
        ]

        let calculator = ProfitReportCalculator()
        let report = calculator.report(year: 2026, invoices: [paidLastYear, open], transactions: transactions)
        #expect(report.income == Money(cents: 70000))
        #expect(report.totalExpenses == Money(cents: 54900))
        #expect(report.profit == Money(cents: 15100))
        #expect(report.monthly[0].income == Money(cents: 70000))
        #expect(report.unreviewedTransactionCount == 1)

        let csv = calculator.csv(for: report)
        #expect(csv.contains("Gewinn;151,00"))
        #expect(csv.contains("Equipment (GWG);549,00"))
    }

    @Test(
        "Small business limits under § 19 UStG",
        arguments: [
            (1_000_000, SmallBusinessStatus.eligible(revenue: Money(cents: 1_000_000))),
            (2_300_000, .approachingLimit(revenue: Money(cents: 2_300_000))),
            (3_000_000, .exceedsNextYearLimit(revenue: Money(cents: 3_000_000))),
        ] as [(Int64, SmallBusinessStatus)]
    )
    func smallBusiness(revenue: Int64, expected: SmallBusinessStatus) throws {
        let invoices = try (1...10).map { index -> Invoice in
            var invoice = try Invoice(
                number: #require(InvoiceNumber(year: 2026, sequence: index)),
                draft: InvoiceDraft(
                    customerID: Fixtures.kantine.id,
                    issueDate: Fixtures.date("2026-06-01"),
                    serviceDate: Fixtures.date("2026-06-01"),
                    lineItems: [LineItem(description: "Gig", unitPrice: Money(cents: revenue / 10))]
                )
            )
            try invoice.issue(on: Fixtures.date("2026-06-01"), archiveDigest: "d")
            return invoice
        }
        #expect(SmallBusinessMonitor().status(year: 2026, invoices: invoices) == expected)
    }
}
