import Foundation
@testable import GageCore
import Testing

@Suite("Invoice numbers and import")
struct ImportAndNumberingTests {
    // Fictional data in the layout of an earlier Pages invoice (as returned by PDF text extraction).
    private static let flatFeeInvoice = """
    Künstlername              Max          +49 170 0000000          Musterweg 1
    E0000.00000000            Beispiel     max@example.de           20000 Musterstadt
    Beispiel Events GmbH & Co. KG
    Hafenstraße 1
    20000 Musterstadt
    RECHNUNGS     RECHNUNGS    BESCHREIBUNG          MENGE      PREIS/H   KOSTEN
    DATUM         NUMMER
    10.11.26      101126
                               Dj Tätigkeit 04.11                         200,00 €
                               ZWISCHENSUMME                              200,00 €
                               Gemäß § 19 UStG wird keine Umsatzsteuer berechnet.
                               Versand                                    0,00 €
                               SUMME                                      200,00 €
    """

    private static let hourlyInvoice = """
    Beispiel Events GmbH & Co. KG
    Hafenstraße 1
    20000 Musterstadt
    RECHNUNGS-    RECHNUNGS    BESCHREIBUNG        MENGE        PREIS/H   KOSTEN
    DATUM         NUMMER
    02.07.26      270626
                               Dj Tätigkeit        5h           20,00 €   100,00 €
                               2 7 . 0 6 . 2 6
                               Gleispark
                               ZWISCHENSUMME                              100,00 €
                               SUMME                                      100,00 €
    """

    private let customer = Customer(
        name: "Beispiel Events GmbH & Co. KG",
        address: PostalAddress(street: "Hafenstraße 1", postalCode: "20000", city: "Musterstadt"),
        email: nil,
        aliases: ["Umbaubar", "Gleispark"]
    )

    @Test("Date-based numbers follow the invoice date and get a suffix on the same day")
    func dateBasedNumbers() throws {
        let date = Fixtures.date("2026-11-10")
        let scheme = InvoiceNumberScheme.invoiceDate
        #expect(scheme.next(issueDate: date, existing: [])?.value == "101126")
        let existing = ["101126", "101126_2"].compactMap(InvoiceNumber.init)
        #expect(scheme.next(issueDate: date, existing: existing)?.value == "101126_3")
        #expect(InvoiceNumber("101126_2")?.year == 2026)
        #expect(InvoiceNumber("2026-014")?.year == 2026)
        #expect(InvoiceNumber("RE 17") == nil)
    }

    @Test("Year sequence numbers count up per year")
    func yearSequenceNumbers() {
        let existing = ["2025-041", "2026-001", "2026-014", "101126"].compactMap(InvoiceNumber.init)
        let scheme = InvoiceNumberScheme.yearSequence
        #expect(scheme.next(issueDate: Fixtures.date("2026-03-01"), existing: existing)?.value == "2026-015")
        #expect(scheme.next(issueDate: Fixtures.date("2027-01-02"), existing: existing)?.value == "2027-001")
    }

    @Test("A draft takes the number of its new invoice date")
    func draftRenumbering() throws {
        var data = Fixtures.appData()
        data.settings.numberScheme = .invoiceDate
        let workflow = BookkeepingWorkflow(digest: TestDigest())
        let now = Fixtures.instant("2026-11-17", hour: 10)
        let invoice = try workflow.createInvoice(from: Fixtures.draft(issued: "2026-11-10"), in: &data, now: now)
        #expect(invoice.number.value == "101126")

        var draft = invoice.draft
        draft.issueDate = Fixtures.date("2026-11-12")
        try workflow.updateInvoice(id: invoice.id, with: draft, in: &data, now: now)
        #expect(data.invoice(withID: invoice.id)?.number.value == "121126")
    }

    @Test("Payment references match whole numbers only")
    func referencesWithSuffix() throws {
        let plain = try #require(InvoiceNumber("101126"))
        let second = try #require(InvoiceNumber("101126_2"))
        #expect(PaymentMatcher.reference("RE101126 Umbaubar", mentions: plain))
        #expect(!PaymentMatcher.reference("Rechnung 101126_2", mentions: plain))
        #expect(PaymentMatcher.reference("Rechnung 101126_2", mentions: second))
        #expect(!PaymentMatcher.reference("1011260", mentions: plain))
    }

    @Test("A flat-fee invoice is read completely")
    func parseFlatFee() throws {
        let parsed = LegacyInvoiceParser.parse(text: Self.flatFeeInvoice, fileName: "Rg_101126_Umbaubar.pdf", customers: [customer])
        #expect(parsed.number?.value == "101126")
        #expect(parsed.issueDate == Fixtures.date("2026-11-10"))
        #expect(parsed.serviceDate == Fixtures.date("2026-11-04"))
        #expect(parsed.total == Money(cents: 20000))
        #expect(parsed.description == "Dj Tätigkeit 04.11")
        #expect(parsed.lineItems.first?.unit == .flatRate)
        #expect(parsed.customerID == customer.id)
        #expect(parsed.venue == "Umbaubar")
        #expect(parsed.recipient?.postalCode == "20000")
        #expect(parsed.warnings.isEmpty)
    }

    @Test("Hours, rate and a letter-spaced date are recognised")
    func parseHourly() throws {
        let parsed = LegacyInvoiceParser.parse(text: Self.hourlyInvoice, fileName: "Rg_260626_Gleispark.pdf", customers: [])
        #expect(parsed.number?.value == "270626")
        #expect(parsed.issueDate == Fixtures.date("2026-07-02"))
        #expect(parsed.serviceDate == Fixtures.date("2026-06-27"))
        let item = try #require(parsed.lineItems.first)
        #expect(item.quantity == 5)
        #expect(item.unit == .hour)
        #expect(item.unitPrice == Money(cents: 2000))
        #expect(parsed.total == Money(cents: 10000))
        #expect(parsed.recipient?.name == "Beispiel Events GmbH & Co. KG")
        #expect(parsed.customerID == nil)
    }

    @Test("Without a year, a gig after the invoice date belongs to the previous year")
    func serviceDateYear() {
        let issue = Fixtures.date("2026-01-05")
        #expect(LegacyInvoiceParser.serviceDate(in: "DJ 30.12", issueDate: issue) == Fixtures.date("2025-12-30"))
        #expect(LegacyInvoiceParser.normalize("D j T ä t i g k e i t") == "Dj Tätigkeit")
    }

    @Test("Imported invoices keep their number, are locked and cannot be imported twice")
    func importInvoice() throws {
        var data = Fixtures.appData()
        data.customers.append(customer)
        let workflow = BookkeepingWorkflow(digest: TestDigest())
        let now = Fixtures.instant("2026-11-17", hour: 10)
        let parsed = LegacyInvoiceParser.parse(text: Self.flatFeeInvoice, fileName: "Rg_101126_Umbaubar.pdf", customers: data.customers)
        let imported = try ImportedInvoice(
            number: #require(parsed.number),
            draft: InvoiceDraft(
                customerID: parsed.customerID,
                issueDate: #require(parsed.issueDate),
                serviceDate: #require(parsed.serviceDate),
                lineItems: parsed.lineItems
            ),
            paidOn: Fixtures.date("2026-11-20"),
            fileName: "Rg_101126_Umbaubar.pdf"
        )
        let archived = ArchivedDocument(url: URL(fileURLWithPath: "/tmp/Rechnung_101126.pdf"), sha256: "original")

        let invoice = try workflow.importInvoice(imported, archived: archived, in: &data, now: now)
        #expect(invoice.number.value == "101126")
        #expect(invoice.source == .imported(fileName: "Rg_101126_Umbaubar.pdf"))
        #expect(invoice.paidOn == Fixtures.date("2026-11-20"))
        #expect(!invoice.isDraft)
        #expect(throws: BookkeepingWorkflow.WorkflowError.duplicateNumber(imported.number)) {
            try workflow.importInvoice(imported, archived: archived, in: &data, now: now)
        }

        // New invoices on the same day continue the old numbering.
        let next = try workflow.createInvoice(from: Fixtures.draft(customer: customer, issued: "2026-11-10"), in: &data, now: now)
        #expect(next.number.value == "101126_2")
    }

    @Test("Stores written before new settings existed still load")
    func backwardCompatibleDecoding() throws {
        let legacySettings = #"{"autoInvoice":{"isEnabled":true,"calendarTitle":"Gigs","hour":9,"minute":0,"excludedEventIDs":[]},"#
            + #""defaultPaymentTermDays":14,"appLockEnabled":true,"autoLockAfterMinutes":5,"bankConnectionEnabled":false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacySettings.utf8))
        #expect(settings.numberScheme == .invoiceDate)
        #expect(settings.bankAccountIBAN == nil)

        var profileJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixtures.profile)) as? [String: Any]
        profileJSON?.removeValue(forKey: "artistName")
        profileJSON?.removeValue(forKey: "logoPNG")
        let legacyProfile = try JSONSerialization.data(withJSONObject: profileJSON ?? [:])
        let profile = try JSONDecoder().decode(BusinessProfile.self, from: legacyProfile)
        #expect(profile.artistName.isEmpty)
        #expect(profile.taxNumber == Fixtures.profile.taxNumber)
    }
}
