import Foundation

public struct MonthlyFigures: Hashable, Sendable, Identifiable {
    public let month: Int
    public let income: Money
    public let expenses: Money

    public var id: Int { month }
}

/// Einnahmen-Überschuss-Rechnung (§ 4 Abs. 3 EStG) for one calendar year.
public struct ProfitReport: Hashable, Sendable {
    public let year: Int
    public let income: Money
    public let expensesByCategory: [ExpenseCategory: Money]
    public let monthly: [MonthlyFigures]
    /// Bookings that still need a decision and are therefore not included.
    public let unreviewedTransactionCount: Int

    public var totalExpenses: Money { expensesByCategory.values.sum() }
    public var profit: Money { income - totalExpenses }
}

/// Builds the EÜR from paid invoices and categorised bookings.
///
/// Income counts in the year the money arrives (Zuflussprinzip, § 11 EStG).
/// The ten-day rule for regularly recurring payments around the turn of the
/// year is not applied automatically. Such cases are rare for small
/// businesses and are listed in docs/domain.md.
public struct ProfitReportCalculator: Sendable {
    public init() {}

    public func report(year: Int, invoices: [Invoice], transactions: [BankTransaction]) -> ProfitReport {
        var monthlyIncome = Array(repeating: Money.zero, count: 12)
        var monthlyExpenses = Array(repeating: Money.zero, count: 12)
        var byCategory = Dictionary(uniqueKeysWithValues: ExpenseCategory.allCases.map { ($0, Money.zero) })

        for invoice in invoices {
            guard let paidOn = invoice.paidOn, paidOn.year == year else { continue }
            monthlyIncome[paidOn.month - 1] += invoice.total
        }

        for transaction in transactions where transaction.bookingDate.year == year {
            let month = transaction.bookingDate.month - 1
            switch transaction.classification {
            case .otherBusinessIncome where transaction.isIncoming:
                monthlyIncome[month] += transaction.amount
            case let .businessExpense(category) where !transaction.isIncoming:
                byCategory[category, default: .zero] += transaction.amount.magnitude
                monthlyExpenses[month] += transaction.amount.magnitude
            default:
                continue
            }
        }

        let unreviewed = transactions.filter { $0.bookingDate.year == year && $0.needsReview }.count
        return ProfitReport(
            year: year,
            income: monthlyIncome.sum(),
            expensesByCategory: byCategory,
            monthly: (0..<12).map { MonthlyFigures(month: $0 + 1, income: monthlyIncome[$0], expenses: monthlyExpenses[$0]) },
            unreviewedTransactionCount: unreviewed
        )
    }

    /// Semicolon-separated CSV for the tax adviser or for copying into ELSTER.
    public func csv(for report: ProfitReport) -> String {
        var rows = ["Position;Betrag EUR"]
        rows.append("Betriebseinnahmen (Kleinunternehmer, § 19 UStG);\(Self.csvAmount(report.income))")
        for category in ExpenseCategory.allCases {
            rows.append("\(category.displayName);\(Self.csvAmount(report.expensesByCategory[category] ?? .zero))")
        }
        rows.append("Summe Betriebsausgaben;\(Self.csvAmount(report.totalExpenses))")
        rows.append("Gewinn;\(Self.csvAmount(report.profit))")
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    private static func csvAmount(_ money: Money) -> String {
        let sign = money.isNegative ? "-" : ""
        let cents = money.magnitude.cents
        return "\(sign)\(cents / 100),\(String(format: "%02d", Int(cents % 100)))"
    }
}

public enum SmallBusinessStatus: Hashable, Sendable {
    case eligible(revenue: Money)
    case approachingLimit(revenue: Money)
    /// Above 25,000 € this year: no small business scheme next year.
    case exceedsNextYearLimit(revenue: Money)
    /// Above 100,000 € this year: VAT applies from the invoice that crossed the limit.
    case exceedsCurrentYearLimit(revenue: Money)
    /// Above 25,000 € last year: the scheme does not apply this year.
    case notEligible(previousYearRevenue: Money)
}

/// Monitors the § 19 UStG limits in force since 2025.
public struct SmallBusinessMonitor: Sendable {
    public static let previousYearLimit = Money(cents: 2_500_000)
    public static let currentYearLimit = Money(cents: 10_000_000)

    public init() {}

    public func revenue(in year: Int, invoices: [Invoice]) -> Money {
        invoices
            .filter { ($0.issuedOn?.year ?? 0) == year }
            .map(\.total)
            .sum()
    }

    public func status(year: Int, invoices: [Invoice]) -> SmallBusinessStatus {
        let previous = revenue(in: year - 1, invoices: invoices)
        let current = revenue(in: year, invoices: invoices)
        if previous > Self.previousYearLimit { return .notEligible(previousYearRevenue: previous) }
        if current > Self.currentYearLimit { return .exceedsCurrentYearLimit(revenue: current) }
        if current > Self.previousYearLimit { return .exceedsNextYearLimit(revenue: current) }
        if current.cents * 10 >= Self.previousYearLimit.cents * 9 { return .approachingLimit(revenue: current) }
        return .eligible(revenue: current)
    }
}
