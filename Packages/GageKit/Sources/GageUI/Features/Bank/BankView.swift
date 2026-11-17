import GageCore
import SwiftUI

struct BankView: View {
    @Environment(AppModel.self) private var model
    @State private var showsReviewOnly = true
    @State private var showsConnectSheet = false

    var body: some View {
        Group {
            if model.data.settings.bankConnectionEnabled {
                transactionsTable
            } else {
                ContentUnavailableView {
                    Label("bunq ist noch nicht verbunden", systemImage: "building.columns")
                } description: {
                    Text("""
                    Verbinde dein Geschäftskonto. \
                    Gage erkennt dann Zahlungseingänge automatisch und ordnet Ausgaben für die EÜR zu. \
                    Gage braucht dafür nur Lesezugriff.
                    """)
                } actions: {
                    Button("bunq verbinden") { showsConnectSheet = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("bunq Konto")
        .toolbar {
            if model.data.settings.bankConnectionEnabled {
                ToolbarItem(placement: .principal) {
                    Picker("Ansicht", selection: $showsReviewOnly) {
                        Text("Zu prüfen (\(model.transactionsNeedingReview.count))").tag(true)
                        Text("Alle Buchungen").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Abrufen", systemImage: "arrow.clockwise") { Task { await model.syncBank() } }
                        .disabled(model.isSyncingBank)
                }
            }
        }
        .sheet(isPresented: $showsConnectSheet) { ConnectBankSheet() }
    }

    private var transactionsTable: some View {
        let transactions = (showsReviewOnly ? model.transactionsNeedingReview : model.data.transactions)
            .sorted { $0.bookingDate > $1.bookingDate }
        return Table(transactions) {
            TableColumn("Datum") { Text($0.bookingDate.germanFormatted).monospacedDigit() }
                .width(min: 80, ideal: 90)
            TableColumn("Gegenpartei") { Text($0.counterpartyName) }
            TableColumn("Verwendungszweck") { Text($0.reference).foregroundStyle(.secondary) }
            TableColumn("Betrag") { transaction in
                Text(transaction.amount.formatted())
                    .monospacedDigit()
                    .foregroundStyle(transaction.isIncoming ? .green : .primary)
            }
            .width(min: 90, ideal: 100)
            TableColumn("Zuordnung") { ClassificationCell(transaction: $0) }
                .width(min: 220, ideal: 260)
        }
        .overlay {
            if transactions.isEmpty {
                EmptyStateView(
                    title: "Alles zugeordnet",
                    systemImage: "checkmark.circle",
                    message: "Neue Buchungen erscheinen hier nach dem Abrufen."
                )
            }
        }
    }
}

private struct ClassificationCell: View {
    @Environment(AppModel.self) private var model
    let transaction: BankTransaction

    var body: some View {
        switch transaction.classification {
        case let .invoicePayment(invoiceID):
            Label("RE \(model.data.invoice(withID: invoiceID)?.number.description ?? "?")", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unreviewed where transaction.isIncoming:
            incomingReview
        default:
            Picker("Kategorie", selection: classificationBinding) {
                Text("Bitte wählen").tag(TransactionClassification.unreviewed)
                if transaction.isIncoming {
                    Text("Sonstige Betriebseinnahme").tag(TransactionClassification.otherBusinessIncome)
                } else {
                    ForEach(ExpenseCategory.allCases) { category in
                        Text(category.displayName).tag(TransactionClassification.businessExpense(category))
                    }
                }
                Divider()
                Text("Privat (nicht betrieblich)").tag(TransactionClassification.privateTransaction)
            }
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var incomingReview: some View {
        let match = model.suggestion(for: transaction)
        if let invoiceID = match.invoiceID, let invoice = model.data.invoice(withID: invoiceID) {
            HStack {
                Text("Vorschlag: RE \(invoice.number)").foregroundStyle(.orange)
                Button("Bestätigen") { Task { await model.confirmSuggestion(for: transaction) } }
            }
        } else {
            Menu("Zuordnen") {
                Button("Sonstige Betriebseinnahme") { Task { await model.classify(transaction, as: .otherBusinessIncome) } }
                Button("Privat") { Task { await model.classify(transaction, as: .privateTransaction) } }
            }
        }
    }

    private var classificationBinding: Binding<TransactionClassification> {
        Binding(
            get: { transaction.classification },
            set: { newValue in Task { await model.classify(transaction, as: newValue) } }
        )
    }
}

private struct ConnectBankSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var isConnecting = false

    var body: some View {
        Form {
            Section {
                SecureField("API-Schlüssel", text: $apiKey)
                    .textContentType(.password)
            } header: {
                Text("bunq API-Schlüssel")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Den Schlüssel erstellst du in der bunq-App unter Profil › Sicherheit & Einstellungen › Entwickler › API-Schlüssel.")
                    Text("Der Schlüssel wird nur im macOS-Schlüsselbund gespeichert. Gage liest Kontoumsätze und kann keine Überweisungen ausführen.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isConnecting ? "Verbinde …" : "Verbinden") {
                    isConnecting = true
                    Task {
                        let connected = await model.connectBank(apiKey: apiKey)
                        apiKey = ""
                        isConnecting = false
                        if connected { dismiss() }
                    }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
            }
        }
    }
}
