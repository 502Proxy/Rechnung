import GageCore
import SwiftUI

struct InvoiceEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: EditorRequest

    @State private var draft: InvoiceDraft?
    @State private var showsValidation = false

    var body: some View {
        Group {
            if let binding = Binding($draft) {
                editor(binding)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .onAppear(perform: prepareDraft)
    }

    private var editingInvoice: Invoice? {
        request.invoiceID.flatMap(model.data.invoice(withID:))
    }

    private func prepareDraft() {
        guard draft == nil else { return }
        draft = editingInvoice?.draft ?? model.newDraft(for: request.gig)
    }

    private func editor(_ draft: Binding<InvoiceDraft>) -> some View {
        let errors = InvoiceValidator().validate(draft.wrappedValue)
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                form(draft, errors: errors).frame(width: 520)
                Divider()
                ScrollView([.vertical, .horizontal]) {
                    InvoiceDocumentView(model: InvoiceDocumentModel(
                        draft: draft.wrappedValue,
                        number: editingInvoice?.number ?? model.predictedNumber(for: draft.wrappedValue.issueDate),
                        customer: draft.wrappedValue.customerID.flatMap(model.data.customer(withID:)),
                        profile: model.data.profile
                    ))
                    .scaleEffect(0.8, anchor: .topLeading)
                    .frame(width: InvoiceDocumentView.pageSize.width * 0.8, height: InvoiceDocumentView.pageSize.height * 0.8, alignment: .topLeading)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(20)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .accessibilityLabel("Vorschau der Rechnung")
            }
            Divider()
            HStack {
                if let gig = request.gig {
                    Label("Aus Kalender: \(gig.title)", systemImage: "calendar").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern") { Task { await save(draft.wrappedValue, send: false, errors: errors) } }
                Button("Speichern & senden") { Task { await save(draft.wrappedValue, send: true, errors: errors) } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    private func form(_ draft: Binding<InvoiceDraft>, errors: [InvoiceValidationError]) -> some View {
        Form {
            Section("Empfänger") {
                Picker("Kunde", selection: draft.customerID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(model.data.customers) { customer in
                        Text(customer.name).tag(UUID?.some(customer.id))
                    }
                }
                if let id = draft.wrappedValue.customerID, model.data.customer(withID: id)?.email == nil {
                    Label("Für diesen Kunden fehlt die E-Mail-Adresse.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section("Daten") {
                DatePicker("Rechnungsdatum", selection: draft.issueDate.asDate, displayedComponents: .date)
                DatePicker("Leistungsdatum", selection: draft.serviceDate.asDate, displayedComponents: .date)
                Picker("Zahlungsziel", selection: draft.paymentTermDays) {
                    ForEach([0, 7, 14, 30], id: \.self) { days in
                        Text(days == 0 ? "Sofort" : "\(days) Tage").tag(days)
                    }
                }
            }
            Section {
                ForEach(draft.lineItems) { $item in
                    LineItemEditor(item: $item) {
                        draft.wrappedValue.lineItems.removeAll { $0.id == item.id }
                    }
                }
                Button("Position hinzufügen", systemImage: "plus") {
                    draft.wrappedValue.lineItems.append(LineItem(description: "", unit: .hour, unitPrice: .zero))
                }
            } header: {
                HStack {
                    Text("Leistungen")
                    Spacer()
                    Text("Summe \(draft.wrappedValue.total.formatted())").monospacedDigit()
                }
            }
            Section("Hinweis auf der Rechnung (optional)") {
                TextField("z. B. Danke für den tollen Abend!", text: draft.note, axis: .vertical)
                    .lineLimit(2...4)
            }
            if showsValidation, !errors.isEmpty {
                Section {
                    ForEach(errors, id: \.self) { error in
                        Label(error.errorDescription ?? "", systemImage: "xmark.octagon").foregroundStyle(.red)
                    }
                }
            }
            Section {
                Label(
                    "Der Hinweis zur Kleinunternehmerregelung und alle Pflichtangaben nach § 14 UStG werden automatisch ergänzt.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func save(_ draft: InvoiceDraft, send: Bool, errors: [InvoiceValidationError]) async {
        guard errors.isEmpty else {
            showsValidation = true
            return
        }
        let source: InvoiceSource = request.gig.map { .gig(eventID: $0.id) } ?? .manual
        guard let invoice = await model.saveDraft(draft, editing: request.invoiceID, source: source) else { return }
        dismiss()
        if send { await model.issueAndSend(invoice.id) }
    }
}

private struct LineItemEditor: View {
    @Binding var item: LineItem
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Beschreibung", text: $item.description, prompt: Text("z. B. DJ-Set, 4 Stunden"))
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Position entfernen")
            }
            HStack {
                TextField("Menge", value: $item.quantity, format: .number)
                    .frame(width: 70)
                Picker("Einheit", selection: $item.unit) {
                    ForEach(BillingUnit.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
                TextField("Preis", value: priceBinding, format: .currency(code: Money.currencyCode))
                    .frame(width: 120)
                Spacer()
                Text(item.total.formatted()).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var priceBinding: Binding<Decimal> {
        Binding(get: { item.unitPrice.decimalValue }, set: { item.unitPrice = Money(euros: $0) })
    }
}
