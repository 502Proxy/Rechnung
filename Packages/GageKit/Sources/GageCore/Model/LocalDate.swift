import Foundation

/// A calendar day without time of day or time zone.
///
/// Invoice, service and booking dates are legal calendar days. Storing them as
/// `Date` would shift them when the Mac changes time zone, so they get their own type.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: Self.utcCalendar) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day `date` falls on in the given calendar's time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1970
        month = components.month ?? 1
        day = components.day ?? 1
    }

    /// Parses `YYYY-MM-DD`.
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func adding(days: Int) -> LocalDate {
        let shifted = Self.utcCalendar.date(byAdding: .day, value: days, to: utcMidnight) ?? utcMidnight
        return LocalDate(shifted, calendar: Self.utcCalendar)
    }

    /// Number of days from `self` to `other` (negative if `other` is earlier).
    public func days(until other: LocalDate) -> Int {
        Self.utcCalendar.dateComponents([.day], from: utcMidnight, to: other.utcMidnight).day ?? 0
    }

    /// The point in time at `hour:minute` on this day in `timeZone`.
    public func date(hour: Int, minute: Int, in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    /// Midnight in the user's current time zone, for SwiftUI date pickers.
    public func startOfDay(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? utcMidnight
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: - Private

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private var utcMidnight: Date {
        Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }
}

extension LocalDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = LocalDate(isoString: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(raw)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
