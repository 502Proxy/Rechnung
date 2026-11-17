import Foundation

/// Recipient read from an old invoice. Used to create a new customer if needed.
public struct ParsedRecipient: Hashable, Sendable {
    public var name: String
    public var street: String
    public var postalCode: String
    public var city: String
}

/// What could be read from an old invoice. Every field is a suggestion for the user to check.
public struct ParsedLegacyInvoice: Hashable, Sendable {
    public var number: InvoiceNumber?
    public var issueDate: LocalDate?
    public var serviceDate: LocalDate?
    public var description: String
    public var lineItems: [LineItem]
    public var total: Money?
    public var customerID: UUID?
    public var recipient: ParsedRecipient?
    public var venue: String?
    public var warnings: [String]
}

/// Reads earlier invoices from their PDF text.
///
/// Tuned to the layout Gage users had in Pages (date, number, description,
/// quantity, price per hour, cost, "SUMME"), with fallbacks for other layouts.
/// The result is never imported without the user's review.
public enum LegacyInvoiceParser {
    private static let amount = #"-?\d{1,3}(?:\.\d{3})*,\d{2}"#
    private static let columnHeaders = #"\b(BESCHREIBUNG|MENGE|PREIS/H|PREIS|KOSTEN|RECHNUNGS-?|DATUM|NUMMER)(?![\p{L}])"#
    private static let legalForms = #"\b(GmbH|UG|AG|KG|e\.\s?V\.|GbR|OHG|mbH|Ltd\.?|Inc\.?)(?![A-Za-z])"#

    public static func parse(text rawText: String, fileName: String, customers: [Customer]) -> ParsedLegacyInvoice {
        let text = normalize(rawText)
        var warnings: [String] = []

        // Number and invoice date: "10.11.26   101126" or "101126_2".
        var number: InvoiceNumber?
        var issueDate: LocalDate?
        var descriptionStart = text.startIndex
        if let match = firstMatch(#"(\d{2}\.\d{2}\.\d{2,4})\s+(\d{6}(?:_\d+)?)(?![\d_])"#, in: text) {
            issueDate = date(from: match.groups[0], referenceYear: nil)
            number = InvoiceNumber(match.groups[1])
            descriptionStart = match.range.upperBound
        }
        if number == nil, let fromFile = firstMatch(#"(?i)rg_(\d{6}(?:_\d+)?)"#, in: fileName) {
            number = InvoiceNumber(fromFile.groups[0])
            warnings.append("Rechnungsnummer aus dem Dateinamen übernommen.")
        }
        if issueDate == nil, let first = firstMatch(#"\b(\d{2}\.\d{2}\.\d{2,4})\b"#, in: text) {
            issueDate = date(from: first.groups[0], referenceYear: nil)
            warnings.append("Rechnungsdatum geschätzt.")
        }
        if number == nil { warnings.append("Keine Rechnungsnummer gefunden.") }
        if issueDate == nil { warnings.append("Kein Rechnungsdatum gefunden.") }

        // Total: the amount after "SUMME", but not "ZWISCHENSUMME".
        var total: Money?
        if let match = firstMatch(#"(?i)(?<!zwischen)summe\s+("# + amount + #")\s*€"#, in: text) {
            total = AmountParser.parse(match.groups[0])
        } else if let last = allMatches("(" + amount + #")\s*€"#, in: text).last {
            total = AmountParser.parse(last.groups[0] ?? "")
            warnings.append("Gesamtbetrag geschätzt.")
        } else {
            warnings.append("Kein Betrag gefunden.")
        }

        // Description: everything between the number and the subtotal.
        let descriptionEnd = text.range(of: "ZWISCHENSUMME", options: .caseInsensitive, range: descriptionStart..<text.endIndex)?.lowerBound
            ?? text.range(of: "SUMME", options: .caseInsensitive, range: descriptionStart..<text.endIndex)?.lowerBound
            ?? descriptionStart
        let block = String(text[descriptionStart..<descriptionEnd])
        let amountsInBlock = allMatches("(" + amount + #")\s*€"#, in: block).compactMap { AmountParser.parse($0.groups[0] ?? "") }
        let hours = firstMatch(#"\b(\d+(?:,\d+)?)\s*h\b"#, in: block)
            .flatMap { Decimal(string: $0.groups[0].replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) }
        let description = block
            .replacingOccurrences(of: columnHeaders, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(" + amount + #")\s*€"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+(?:,\d+)?\s*h\b"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let serviceDate = serviceDate(in: description, issueDate: issueDate)
        if serviceDate == nil { warnings.append("Leistungsdatum nicht erkannt, Rechnungsdatum verwendet.") }

        // Line item: hours × rate when the numbers add up, otherwise a flat fee.
        var lineItems: [LineItem] = []
        if let total {
            let itemDescription = description.isEmpty ? "DJ-Tätigkeit" : description
            if let hours, hours > 0, let rate = amountsInBlock.first(where: { $0 != total }), rate.multiplied(by: hours) == total {
                lineItems = [LineItem(description: itemDescription, quantity: hours, unit: .hour, unitPrice: rate)]
            } else {
                lineItems = [LineItem(description: itemDescription, unitPrice: total)]
            }
        }

        let venue = firstMatch(#"(?i)rg_\d{6}(?:_\d+)?_([^._]+)"#, in: fileName)?.groups[0].trimmingCharacters(in: .whitespaces)
        let recipient = recipient(in: text)
        let customerID = matchCustomer(customers, venue: venue, recipient: recipient, text: text)
        if customerID == nil, recipient == nil { warnings.append("Kunde nicht erkannt.") }

        return ParsedLegacyInvoice(
            number: number,
            issueDate: issueDate,
            serviceDate: serviceDate ?? issueDate,
            description: description,
            lineItems: lineItems,
            total: total,
            customerID: customerID,
            recipient: recipient,
            venue: venue,
            warnings: warnings
        )
    }

    // MARK: - Helpers

    /// Joins characters spread out by justified text: "2 7 . 0 6 . 2 6" → "27.06.26",
    /// "D j T ä t i g k e i t" → "Dj Tätigkeit".
    static func normalize(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
        for match in allMatches(#"(?<!\S)(?:[\d.] ){3,}[\d.](?!\S)"#, in: result).reversed() {
            result.replaceSubrange(match.range, with: result[match.range].filter { $0 != " " })
        }
        for match in allMatches(#"(?<!\S)(?:\p{L} ){3,}\p{L}(?!\S)"#, in: result).reversed() {
            let joined = String(result[match.range].filter { $0 != " " })
            let separated = joined.replacingOccurrences(of: #"(?<=\p{Ll})(?=\p{Lu})"#, with: " ", options: .regularExpression)
            result.replaceSubrange(match.range, with: separated)
        }
        return result
    }

    static func date(from text: String, referenceYear: Int?) -> LocalDate? {
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        var year = parts.count >= 3 ? parts[2] : (referenceYear ?? 0)
        if year < 100 { year += 2000 }
        return LocalDate(year: year, month: parts[1], day: parts[0])
    }

    /// Finds "04.11", "14.10.26" or "22.07.2026" in the description. Without a year, the gig
    /// lies in the year of the invoice, or the year before if it would otherwise be after the invoice.
    static func serviceDate(in description: String, issueDate: LocalDate?) -> LocalDate? {
        guard let match = firstMatch(#"\b(\d{1,2})\.(\d{1,2})\.?(\d{4}|\d{2})?\b"#, in: description) else { return nil }
        let day = Int(match.groups[0]) ?? 0
        let month = Int(match.groups[1]) ?? 0
        if var year = Int(match.groups[2]) {
            if year < 100 { year += 2000 }
            return LocalDate(year: year, month: month, day: day)
        }
        guard let issueDate else { return nil }
        guard let sameYear = LocalDate(year: issueDate.year, month: month, day: day) else { return nil }
        return sameYear > issueDate ? LocalDate(year: issueDate.year - 1, month: month, day: day) : sameYear
    }

    /// The first line with a legal form (GmbH, KG, …) plus street and postcode line after it.
    static func recipient(in text: String) -> ParsedRecipient? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        guard let index = lines.firstIndex(where: { $0.range(of: legalForms, options: .regularExpression) != nil }) else {
            return nil
        }
        let following = lines.dropFirst(index + 1).prefix(3)
        guard let cityIndex = following.firstIndex(where: { $0.range(of: #"^\d{5}\s"#, options: .regularExpression) != nil }) else {
            return ParsedRecipient(name: lines[index], street: "", postalCode: "", city: "")
        }
        let cityLine = lines[cityIndex]
        let street = cityIndex > index + 1 ? lines[cityIndex - 1] : ""
        return ParsedRecipient(
            name: lines[index],
            street: street,
            postalCode: String(cityLine.prefix(5)),
            city: String(cityLine.dropFirst(6))
        )
    }

    static func matchCustomer(_ customers: [Customer], venue: String?, recipient: ParsedRecipient?, text: String) -> UUID? {
        let candidates = [recipient?.name, venue].compactMap { $0 }.filter { !$0.isEmpty }
        for candidate in candidates {
            let matches = customers.filter { customer in
                ([customer.name] + customer.aliases).contains { PaymentMatcher.namesResemble($0, candidate) }
            }
            if matches.count == 1 { return matches.first?.id }
        }
        let mentioned = customers.filter { text.range(of: $0.name, options: .caseInsensitive) != nil }
        return mentioned.count == 1 ? mentioned.first?.id : nil
    }

    struct Match {
        let range: Range<String.Index>
        let groups: [String?]
    }

    static func firstMatch(_ pattern: String, in text: String) -> (range: Range<String.Index>, groups: [String])? {
        guard let match = allMatches(pattern, in: text).first else { return nil }
        return (match.range, match.groups.map { $0 ?? "" })
    }

    static func allMatches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let groups = (1..<max(1, result.numberOfRanges)).map { index -> String? in
                guard result.numberOfRanges > index, let groupRange = Range(result.range(at: index), in: text) else { return nil }
                return String(text[groupRange])
            }
            return Match(range: range, groups: groups)
        }
    }
}
