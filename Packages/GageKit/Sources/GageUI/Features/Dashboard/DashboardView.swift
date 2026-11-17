import GageCore
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigation.self) private var navigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                kpis
                HStack(alignment: .top, spacing: Theme.spacing) {
                    todoList.frame(maxWidth: .infinity)
                    VStack(spacing: Theme.spacing) {
                        nextGig
                        smallBusinessCard
                    }
                    .frame(width: 320)
                }
            }
            .padding(20)
        }
        .navigationTitle("Übersicht")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Neue Rechnung", systemImage: "plus") { navigation.newInvoice() }
            }
        }
    }

    // MARK: Sections

    private var kpis: some View {
        let report = model.report(year: model.today.year)
        let open = model.invoices(in: .open) + model.invoices(in: .overdue)
        let overdue = model.invoices(in: .overdue)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            KPITile(title: "Einnahmen \(String(model.today.year))", value: report.income.formatted(), footnote: "nach Zahlungseingang")
            KPITile(title: "Offene Rechnungen", value: open.map(\.total).sum().formatted(), footnote: "\(open.count) offen")
            KPITile(
                title: "Davon überfällig",
                value: overdue.map(\.total).sum().formatted(),
                footnote: "\(overdue.count) überfällig",
                tone: overdue.isEmpty ? .primary : .red
            )
            KPITile(title: "Vorläufiger Gewinn", value: report.profit.formatted(), footnote: "Ausgaben \(report.totalExpenses.formatted())")
        }
    }

    private var todoList: some View {
        GroupBox {
            let drafts = model.invoices(in: .draft)
            let overdue = model.invoices(in: .overdue)
            let review = model.transactionsNeedingReview
            if drafts.isEmpty, overdue.isEmpty, review.isEmpty, model.unresolvedGigs.isEmpty {
                EmptyStateView(title: "Alles erledigt", systemImage: "checkmark.seal", message: "Neue Aufgaben erscheinen hier automatisch.")
                    .frame(minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    ForEach(drafts) { invoice in
                        TodoRow(
                            systemImage: "doc.text",
                            tint: Theme.accent,
                            title: "Rechnung \(invoice.number) prüfen und senden",
                            subtitle: "\(model.customer(for: invoice)?.name ?? "") · \(invoice.total.formatted())",
                            actionTitle: "Prüfen"
                        ) { navigation.editor = EditorRequest(invoiceID: invoice.id, gig: nil) }
                    }
                    ForEach(overdue) { invoice in
                        TodoRow(
                            systemImage: "exclamationmark.triangle",
                            tint: .red,
                            title: "\(invoice.number) ist seit \(invoice.dueDate.days(until: model.today)) Tagen überfällig",
                            subtitle: "\(model.customer(for: invoice)?.name ?? "") · \(invoice.total.formatted())",
                            actionTitle: "Erinnern"
                        ) { Task { await model.sendReminder(invoice.id) } }
                    }
                    if !review.isEmpty {
                        TodoRow(
                            systemImage: "eurosign.circle",
                            tint: .orange,
                            title: "\(review.count) Buchung(en) prüfen",
                            subtitle: "Zahlungseingänge zuordnen oder Ausgaben kategorisieren",
                            actionTitle: "Öffnen"
                        ) { navigation.selection = .bank }
                    }
                    ForEach(model.unresolvedGigs) { gig in
                        TodoRow(
                            systemImage: "calendar.badge.exclamationmark",
                            tint: .orange,
                            title: "Kunde für „\(gig.title)“ unklar",
                            subtitle: "Ergänze „Kunde: …“ in der Kalendernotiz oder lege den Kunden an.",
                            actionTitle: "Rechnung erstellen"
                        ) { navigation.editor = EditorRequest(invoiceID: nil, gig: gig) }
                    }
                }
            }
        } label: {
            Label("Zu erledigen", systemImage: "checklist")
        }
    }

    private var nextGig: some View {
        GroupBox {
            if let gig = model.gigs.filter({ $0.start >= Date() }).min(by: { $0.start < $1.start }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(gig.title).font(.headline)
                    Text(gig.start.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
                    if let planned = model.plannedInvoiceDate(for: gig), let fee = gig.fee {
                        Label(
                            "Rechnung über \(fee.formatted()) am \(planned.formatted(date: .abbreviated, time: .shortened))",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.callout)
                    } else {
                        Label("Keine automatische Rechnung", systemImage: "pause.circle").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine anstehenden Gigs im Kalender „\(model.data.settings.autoInvoice.calendarTitle)“.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Nächster Gig", systemImage: "music.mic")
        }
    }

    private var smallBusinessCard: some View {
        GroupBox {
            let limit = SmallBusinessMonitor.previousYearLimit
            let revenue = SmallBusinessMonitor().revenue(in: model.today.year, invoices: model.data.invoices)
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: min(Double(revenue.cents), Double(limit.cents)), total: Double(limit.cents)) {
                    Text("Umsatz \(String(model.today.year))")
                } currentValueLabel: {
                    Text("\(revenue.formatted()) von \(limit.formatted())").monospacedDigit()
                }
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            Label("Kleinunternehmerregelung § 19 UStG", systemImage: "gauge.with.dots.needle.33percent")
        }
    }

    private var statusText: String {
        switch model.smallBusinessStatus {
        case .eligible:
            "Du liegst unter 25.000 €. Damit bleibst du auch nächstes Jahr Kleinunternehmer."
        case .approachingLimit:
            "Achtung: Du hast über 90 % der Grenze von 25.000 € erreicht."
        case .exceedsNextYearLimit:
            "Über 25.000 €: Ab dem nächsten Jahr gilt die Kleinunternehmerregelung nicht mehr. Sprich mit deiner Steuerberatung."
        case .exceedsCurrentYearLimit:
            "Über 100.000 €: Ab sofort musst du Umsatzsteuer ausweisen. Sprich umgehend mit deiner Steuerberatung."
        case .notEligible:
            "Im Vorjahr lag dein Umsatz über 25.000 €. Die Kleinunternehmerregelung gilt dieses Jahr nicht."
        }
    }
}

private struct TodoRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
        }
        .padding(.vertical, 8)
    }
}
