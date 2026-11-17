import GageCore
import SwiftUI

struct GigsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.calendarNeedsSelection {
                CalendarSelection()
            }
            Section {
                HowItWorks(calendarTitle: model.data.settings.autoInvoice.calendarTitle, hour: model.data.settings.autoInvoice.hour)
            }
            Section("Gigs") {
                if model.gigs.isEmpty {
                    Text("""
                    Keine Termine gefunden. \
                    Lege im Kalender „\(model.data.settings.autoInvoice.calendarTitle)“ Termine mit „Gage: 800“ in der Notiz an.
                    """)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.gigs) { gig in
                    GigRow(gig: gig)
                }
            }
        }
        .navigationTitle("Gigs & Kalender")
        .toolbar {
            Button("Kalender abrufen", systemImage: "arrow.clockwise") { Task { await model.syncCalendar() } }
                .disabled(model.isSyncingCalendar)
        }
        .task { await model.syncCalendar() }
    }
}

/// Shown when the configured calendar does not exist on this Mac.
private struct CalendarSelection: View {
    @Environment(AppModel.self) private var model
    @State private var choice = ""

    var body: some View {
        Section {
            Picker("Gig-Kalender", selection: $choice) {
                Text("Bitte wählen").tag("")
                ForEach(model.calendarTitles, id: \.self) { Text($0).tag($0) }
            }
            Button("Übernehmen") { Task { await model.selectCalendar(choice) } }
                .buttonStyle(.borderedProminent)
                .disabled(choice.isEmpty)
        } header: {
            Label(
                "Der Kalender „\(model.data.settings.autoInvoice.calendarTitle)“ existiert auf diesem Mac nicht",
                systemImage: "calendar.badge.exclamationmark"
            )
            .foregroundStyle(.orange)
        } footer: {
            Text("Wähle den Kalender, in dem deine Auftritte stehen. Du kannst ihn später in den Einstellungen ändern.")
        }
        .task { await model.loadCalendarTitles() }
    }
}

private struct GigRow: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigation.self) private var navigation
    let gig: Gig

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(gig.start.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .background(.red)
                Text(gig.start.formatted(.dateTime.day())).font(.title3.weight(.semibold)).padding(.vertical, 2)
            }
            .frame(width: 48)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))

            VStack(alignment: .leading, spacing: 2) {
                Text(gig.title).fontWeight(.semibold)
                Text([gig.start.formatted(date: .omitted, time: .shortened), gig.location].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(model.resolvedCustomer(for: gig)?.name ?? "Kunde unklar")
                    if let fee = gig.fee {
                        Text("· Gage \(fee.formatted())").monospacedDigit()
                    } else {
                        Text("· keine Gage in der Notiz").foregroundStyle(.orange)
                    }
                }
                .font(.callout)
            }
            Spacer()
            status
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var status: some View {
        if let invoice = model.invoice(for: gig) {
            HStack {
                StatusBadge(state: invoice.state(asOf: model.today))
                Text(invoice.number.description).monospacedDigit().foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 12) {
                if let planned = model.plannedInvoiceDate(for: gig) {
                    Text("Rechnung am \(planned.formatted(date: .abbreviated, time: .shortened))")
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                } else {
                    Button("Rechnung jetzt erstellen") { navigation.editor = EditorRequest(invoiceID: nil, gig: gig) }
                }
                Toggle("Automatisch abrechnen", isOn: Binding(
                    get: { !model.data.settings.autoInvoice.excludedEventIDs.contains(gig.id) },
                    set: { enabled in Task { await model.setAutoInvoice(enabled, for: gig) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(gig.fee == nil)
                .help("Rechnung am Tag nach dem Gig automatisch als Entwurf erstellen")
            }
        }
    }
}

private struct HowItWorks: View {
    let calendarTitle: String
    let hour: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            step("1 · Kalender", "Termin im Kalender „\(calendarTitle)“ mit „Gage: …“ in der Notiz")
            step("2 · Am Tag danach, \(hour) Uhr", "Gage erstellt die Rechnung als Entwurf")
            step("3 · Prüfen", "Du bekommst eine Mitteilung und sendest mit einem Klick")
            step("4 · bunq", "Der Zahlungseingang wird erkannt, die Rechnung gilt als bezahlt")
        }
        .padding(.vertical, 6)
    }

    private func step(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(text).font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
