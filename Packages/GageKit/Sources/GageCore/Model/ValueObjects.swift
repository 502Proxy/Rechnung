import Foundation

/// A syntactically valid e-mail address.
///
/// The strict pattern also rules out line breaks, so no address can inject
/// extra mail headers.
public struct EmailAddress: Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 254,
              !trimmed.contains(".."),
              trimmed.range(
                  of: #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$"#,
                  options: .regularExpression
              ) != nil
        else { return nil }
        value = trimmed
    }

    public var description: String { value }
}

extension EmailAddress: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = EmailAddress(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid e-mail address")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// An IBAN whose ISO 13616 check digits are valid.
public struct IBAN: Hashable, Sendable, CustomStringConvertible {
    /// Upper case, no spaces, e.g. `DE89370400440532013000`.
    public let electronicFormat: String

    public init?(_ raw: String) {
        let compact = raw.uppercased().filter { !$0.isWhitespace }
        guard (15...34).contains(compact.count),
              compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              compact.prefix(2).allSatisfy(\.isLetter),
              compact.dropFirst(2).prefix(2).allSatisfy(\.isNumber),
              Self.hasValidChecksum(compact)
        else { return nil }
        electronicFormat = compact
    }

    /// Groups of four, e.g. `DE89 3704 0044 0532 0130 00`.
    public var formatted: String {
        var result = ""
        for (index, character) in electronicFormat.enumerated() {
            if index > 0, index.isMultiple(of: 4) { result.append(" ") }
            result.append(character)
        }
        return result
    }

    public var description: String { formatted }

    private static func hasValidChecksum(_ iban: String) -> Bool {
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rearranged {
            let value: Int
            if let digit = character.wholeNumberValue {
                value = digit
            } else if let ascii = character.asciiValue, character.isLetter {
                value = Int(ascii) - 55 // A = 10 … Z = 35
            } else {
                return false
            }
            for digit in String(value) {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }
}

extension IBAN: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = IBAN(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid IBAN")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(electronicFormat)
    }
}

public struct PostalAddress: Hashable, Sendable, Codable {
    public var street: String
    public var postalCode: String
    public var city: String
    /// ISO 3166-1 alpha-2.
    public var countryCode: String

    public init(street: String, postalCode: String, city: String, countryCode: String = "DE") {
        self.street = street
        self.postalCode = postalCode
        self.city = city
        self.countryCode = countryCode
    }

    public var lines: [String] {
        var lines = [street, "\(postalCode) \(city)"]
        if countryCode != "DE" { lines.append(countryCode) }
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public var isComplete: Bool {
        ![street, postalCode, city].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
