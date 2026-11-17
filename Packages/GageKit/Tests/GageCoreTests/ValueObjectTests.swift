import Foundation
@testable import GageCore
import Testing

@Suite("Value objects")
struct ValueObjectTests {
    @Test("Money rounds half up to the cent")
    func moneyRounding() {
        #expect(Money(euros: Fixtures.decimal("10.005")).cents == 1001)
        #expect(Money(cents: 3333).multiplied(by: 3).cents == 9999)
        #expect(Money(cents: 1000).multiplied(by: Fixtures.decimal("0.5")).cents == 500)
        #expect([Money(cents: 150), Money(cents: 250)].sum() == Money(cents: 400))
    }

    @Test("Money formats in German notation")
    func moneyFormatting() {
        let text = Money(cents: 140_050).formatted()
        #expect(text.contains("1.400,50"))
        #expect(text.contains("€"))
    }

    @Test(
        "Amounts as written in notes",
        arguments: [
            ("1.400", 140_000),
            ("1400", 140_000),
            ("1.400,50 €", 140_050),
            ("950,5", 95050),
            ("EUR 700", 70000),
            ("12.5", 1250),
            ("1.400.000", 140_000_000),
        ] as [(String, Int64)]
    )
    func amountParsing(input: String, cents: Int64) {
        #expect(AmountParser.parse(input)?.cents == cents)
    }

    @Test("Rejects input that is not an amount", arguments: ["", "abc", "1.2.3", "12,345", "1e5", "--5", "12abc"])
    func amountParsingRejects(input: String) {
        #expect(AmountParser.parse(input) == nil)
    }

    @Test("IBAN check digits")
    func iban() throws {
        let iban = try #require(IBAN("de89 3704 0044 0532 0130 00"))
        #expect(iban.electronicFormat == "DE89370400440532013000")
        #expect(iban.formatted == "DE89 3704 0044 0532 0130 00")
        #expect(IBAN("DE89 3704 0044 0532 0130 01") == nil)
        #expect(IBAN("NL91ABNA0417164300") != nil)
        #expect(IBAN("DE89") == nil)
    }

    @Test("E-mail addresses cannot carry header line breaks")
    func email() {
        #expect(EmailAddress("rechnung@example.de") != nil)
        #expect(EmailAddress("  max.beispiel+gage@mail.example.org ") != nil)
        #expect(EmailAddress("a@b") == nil)
        #expect(EmailAddress("a..b@example.de") == nil)
        #expect(EmailAddress("x@example.de\nBcc: evil@example.de") == nil)
    }

    @Test("LocalDate arithmetic across months and leap years")
    func localDate() throws {
        let date = try #require(LocalDate(year: 2028, month: 2, day: 28))
        #expect(date.adding(days: 1).description == "2028-02-29")
        #expect(date.adding(days: 2).description == "2028-03-01")
        #expect(date.days(until: date.adding(days: 14)) == 14)
        #expect(LocalDate(year: 2026, month: 2, day: 29) == nil)
        #expect(LocalDate(isoString: "2026-11-17") == LocalDate(year: 2026, month: 11, day: 17))
        #expect(LocalDate(isoString: "2026-1-17") == nil)
    }

    @Test("LocalDate survives encoding as YYYY-MM-DD")
    func localDateCodable() throws {
        let date = try #require(LocalDate(year: 2026, month: 11, day: 17))
        let data = try JSONEncoder().encode([date])
        #expect(String(data: data, encoding: .utf8) == #"["2026-11-17"]"#)
        #expect(try JSONDecoder().decode([LocalDate].self, from: data) == [date])
    }

    @Test("Invoice numbers accept common formats and reject unsafe characters")
    func invoiceNumbers() {
        #expect(InvoiceNumber(" 101126_2 ")?.value == "101126_2")
        #expect(InvoiceNumber("2026-1000") != nil)
        #expect(InvoiceNumber("") == nil)
        #expect(InvoiceNumber("../etc") == nil)
        #expect(InvoiceNumber("2026/015") == nil)
        #expect(InvoiceNumber(".hidden") == nil)
        #expect(InvoiceNumber(String(repeating: "1", count: 41)) == nil)
    }
}
