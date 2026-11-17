import GageCore
import SwiftUI

/// Colours and spacing used across the app. Semantic colours come from the system and so follow light and dark mode.
public enum Theme {
    /// Dark petrol: calm and businesslike, readable on light and dark backgrounds.
    public static let accent = Color(red: 0.05, green: 0.42, blue: 0.40)
    static let spacing: CGFloat = 16
    static let cornerRadius: CGFloat = 10
}

struct StatusBadge: View {
    let state: InvoiceState

    var body: some View {
        Text(state.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityLabel("Status: \(state.displayName)")
    }

    private var color: Color {
        switch state {
        case .draft: .secondary
        case .open: .blue
        case .overdue: .red
        case .paid: .green
        }
    }
}

struct KPITile: View {
    let title: String
    let value: String
    let footnote: String
    var tone: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
            Text(footnote).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(.background, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(.separator))
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

extension Binding where Value == LocalDate {
    /// Connects a `LocalDate` to a SwiftUI `DatePicker`.
    var asDate: Binding<Date> {
        Binding<Date>(
            get: { wrappedValue.startOfDay() },
            set: { wrappedValue = LocalDate($0) }
        )
    }
}

extension LocalDate {
    var germanFormatted: String { MailTemplates.format(self) }
}
