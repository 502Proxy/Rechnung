import Foundation

/// An amount in euros, stored as whole cents.
///
/// Integer cents rule out the rounding drift of binary floating point. Every
/// multiplication rounds to the cent right away ("kaufmännisch", half up).
public struct Money: Hashable, Comparable, Sendable, Codable {
    public static let currencyCode = "EUR"
    public static let zero = Money(cents: 0)

    public let cents: Int64

    public init(cents: Int64) {
        self.cents = cents
    }

    public init(euros: Decimal) {
        cents = Self.roundedInt64(euros * 100)
    }

    public var decimalValue: Decimal {
        Decimal(cents) / 100
    }

    public var isPositive: Bool { cents > 0 }
    public var isNegative: Bool { cents < 0 }
    public var magnitude: Money { Money(cents: cents == .min ? .max : Swift.abs(cents)) }

    public func multiplied(by factor: Decimal) -> Money {
        Money(cents: Self.roundedInt64(Decimal(cents) * factor))
    }

    public func formatted(locale: Locale = Locale(identifier: "de_DE")) -> String {
        decimalValue.formatted(.currency(code: Self.currencyCode).locale(locale))
    }

    public static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }
    public static prefix func - (value: Money) -> Money { Money(cents: -value.cents) }
    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    public static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }
    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }

    private static func roundedInt64(_ value: Decimal) -> Int64 {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return NSDecimalNumber(decimal: result).int64Value
    }
}

extension Sequence where Element == Money {
    public func sum() -> Money {
        reduce(.zero, +)
    }
}

/// Parses amounts as people type them in German notes: "1.400", "1400,50 €", "EUR 950".
public enum AmountParser {
    public static func parse(_ raw: String) -> Money? {
        var text = raw
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive)
            .filter { !$0.isWhitespace }

        if text.contains(",") {
            // German notation: dots group thousands, the comma separates cents.
            text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            let groups = text.split(separator: ".", omittingEmptySubsequences: false)
            if groups.count > 1, groups.dropFirst().allSatisfy({ $0.count == 3 }) {
                // "1.400" means one thousand four hundred, not 1.4.
                text = text.replacingOccurrences(of: ".", with: "")
            }
        }

        guard text.range(of: #"^-?[0-9]{1,9}(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return Money(euros: value)
    }
}
