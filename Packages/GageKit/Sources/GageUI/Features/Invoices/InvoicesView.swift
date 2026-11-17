import GageCore
import SwiftUI

struct InvoicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigation.self) private var navigation
    @State private var filter: InvoiceState?
    @State private var selection: Invoice.ID?
    @State private var showsImport = false

    var body: some View {
        let invoices = model.invoices(in: filter)
        HSplitView {
            Table(invoices, selection: $selection) {
                TableColumn("Nr.") { Text($0.number.description).monospacedDigit() }
                    .width(min: 70, ideal: 80)
                TableColumn("Kunde") { invoice in
                    VStack(alignment: .leading) {
                        Text(model.customer(for: invoice)?.name ?? "–")
                        Text(invoice.lineItems.first?.description ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
                TableColumn("Datum") { Text($0.issueDate.germanFormatted).monospacedDigit() }
                    .width(min: 80, ideal: 90)
                TableColumn("Betrag") { Text($0.total.formatted()).monospacedDigit() }
                    .width(min: 80, ideal: 100)
                TableColumn("Status") { StatusBadge(state: $0.state(asOf: model.today)) }
                    .width(min: 80, ideal: 100)
            }
            .frame(minWidth: 420)
            .overlay {
                if invoices.isEmpty {
                    EmptyStateView(title: "Keine Rechnungen", systemImage: "doc.text", message: "Erstelle deine erste Rechnung mit ⌘N.")
                }
            }

            Group {
                if let id = selection, let invoice = model.data.invoice(withID: id) {
                    InvoiceDetailView(invoice: invoice)
                } else {
                    EmptyStateView(
                        title: "Keine Rechnung ausgewählt",
                        systemImage: "doc.text.magnifyingglass",
                        message: "Wähle links eine Rechnung aus."
                    )
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Rechnungen")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Filter", selection: $filter) {
                    Text("Alle").tag(InvoiceState?.none)
                    ForEach(InvoiceState.allCases, id: \.self) { state in
                        Text(state.displayName).tag(InvoiceState?.some(state))
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Alte Rechnungen importieren", systemImage: "square.and.arrow.down") { showsImport = true }
                    .help("Frühere Rechnungen als PDF übernehmen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Neue Rechnung", systemImage: "plus") { navigation.newInvoice() }
            }
        }
        .sheet(isPresented: $showsImport) {
            ImportInvoicesView().environment(model)
        }
    }
}

struct InvoiceDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigation.self) private var navigation
    let invoice: Invoice

    var body: some View {
        let state = invoice.state(asOf: model.today)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StatusBadge(state: state)
                Text(statusLine(for: state)).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)

            HStack(spacing: 8) {
                switch state {
                case .draft:
                    Button("Senden", systemImage: "paperplane") { Task { await model.issueAndSend(invoice.id) } }
                        .buttonStyle(.borderedProminent)
                    Button("Bearbeiten", systemImage: "pencil") {
                        navigation.editor = EditorRequest(invoiceID: invoice.id, gig: nil)
                    }
                case .open, .overdue:
                    if state == .overdue {
                        Button("Zahlungserinnerung", systemImage: "bell") { Task { await model.sendReminder(invoice.id) } }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Als bezahlt markieren", systemImage: "checkmark") { Task { await model.markPaid(invoice.id) } }
                case .paid:
                    EmptyView()
                }
                if !invoice.isDraft {
                    Button("Im Finder zeigen", systemImage: "folder") { Task { await model.revealInFinder(invoice.id) } }
                    Button("Integrität prüfen", systemImage: "checkmark.shield") { Task { await model.verifyArchive(invoice.id) } }
                }
                Spacer()
            }
            .padding([.horizontal, .bottom], 12)

            Divider()
            ScrollView([.vertical, .horizontal]) {
                InvoiceDocumentView(model: InvoiceDocumentModel(
                    invoice: invoice,
                    customer: model.customer(for: invoice),
                    profile: model.data.profile,
                    isDraft: invoice.isDraft
                ))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .padding(24)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private func statusLine(for state: InvoiceState) -> String {
        switch state {
        case .draft: invoice.source == .manual ? "Noch nicht versendet" : "Automatisch aus dem Kalender erstellt"
        case .open: "Gesendet am \(invoice.issuedOn?.germanFormatted ?? "–") · fällig \(invoice.dueDate.germanFormatted)"
        case .overdue: "Fällig seit \(invoice.dueDate.germanFormatted)"
        case .paid: "Bezahlt am \(invoice.paidOn?.germanFormatted ?? "–")"
        }
    }
}
