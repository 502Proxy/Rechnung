import GageCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// One earlier invoice during import: what was read from the PDF and what the user confirmed.
struct LegacyImportCandidate: Identifiable {
    enum CustomerChoice: Hashable {
        case existing(UUID)
        case new(ParsedRecipient)
        case none
    }

    let id = UUID()
    let fileName: String
    let pdfData: Data
    let parsed: ParsedLegacyInvoice
    var numberText: String
    var issueDate: LocalDate
    var serviceDate: LocalDate
    var description: String
    var total: Decimal
    var customerChoice: CustomerChoice
    var isPaid: Bool
    var paidOn: LocalDate
    var isIncluded: Bool

    static let maximumFileSize = 20 * 1024 * 1024

    init(fileName: String, pdfData: Data, customers: [Customer], today: LocalDate) {
        let text = PDFDocument(data: pdfData)?.string ?? ""
        let parsed = LegacyInvoiceParser.parse(text: text, fileName: fileName, customers: customers)
        self.fileName = fileName
        self.pdfData = pdfData
        self.parsed = parsed
        numberText = parsed.number?.value ?? ""
        issueDate = parsed.issueDate ?? today
        serviceDate = parsed.serviceDate ?? parsed.issueDate ?? today
        description = parsed.description.isEmpty ? "DJ-Tätigkeit" : parsed.description
        total = parsed.total?.decimalValue ?? 0
        if let id = parsed.customerID {
            customerChoice = .existing(id)
        } else if let recipient = parsed.recipient {
            customerChoice = .new(recipient)
        } else {
            customerChoice = .none
        }
        // Older invoices are usually paid. The user confirms it; bunq can also match them later.
        isPaid = (parsed.issueDate ?? today).days(until: today) > 30
        paidOn = (parsed.issueDate ?? today).adding(days: 14)
        isIncluded = parsed.number != nil && parsed.total != nil
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isIncluded = false
        }
    }

    var hasText: Bool { parsed.number != nil || parsed.total != nil || !parsed.description.isEmpty }

    /// Keeps hours × rate if the user did not change the amount, otherwise one flat item.
    func draft(customerID: UUID) -> InvoiceDraft {
        let money = Money(euros: total)
        let items: [LineItem]
        if parsed.lineItems.count == 1, var item = parsed.lineItems.first, item.total == money {
            item.description = description
            items = [item]
        } else {
            items = [LineItem(description: description, unitPrice: money)]
        }
        return InvoiceDraft(
            customerID: customerID,
            issueDate: issueDate,
            serviceDate: serviceDate,
            paymentTermDays: 14,
            lineItems: items
        )
    }
}

struct ImportInvoicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [LegacyImportCandidate] = []
    @State private var showsFilePicker = false
    @State private var isImporting = false
    @State private var skippedFiles: [String] = []

    private var includedCount: Int { candidates.filter(\.isIncluded).count }

    var body: some View {
        VStack(spacing: 0) {
            if candidates.isEmpty {
                dropZone
            } else {
                List {
                    if !skippedFiles.isEmpty {
                        Label("Übersprungen: \(skippedFiles.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    ForEach($candidates) { $candidate in
                        CandidateRow(candidate: $candidate, customers: model.data.customers)
                    }
                }
            }
            Divider()
            HStack {
                Text("Die Original-PDFs werden unverändert und schreibgeschützt archiviert.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !candidates.isEmpty {
                    Button("Weitere PDFs …") { showsFilePicker = true }
                    Button(isImporting ? "Importiere …" : "\(includedCount) Rechnung(en) importieren") {
                        isImporting = true
                        Task {
                            await model.importLegacyInvoices(candidates)
                            isImporting = false
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(includedCount == 0 || isImporting)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 860, minHeight: 620)
        .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { load(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            load(urls)
            return true
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.doc").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text("Alte Rechnungen importieren").font(.title2.weight(.semibold))
            Text("Ziehe deine PDF-Rechnungen hierher oder wähle sie aus. Du prüfst jede Rechnung, bevor sie übernommen wird.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("PDFs auswählen …") { showsFilePicker = true }
                .buttonStyle(.borderedProminent)
            Text("Rechnungen aus Pages zuerst als PDF exportieren (Ablage › Exportieren › PDF).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func load(_ urls: [URL]) {
        for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard url.pathExtension.lowercased() == "pdf",
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= LegacyImportCandidate.maximumFileSize,
                  let data = try? Data(contentsOf: url),
                  data.starts(with: Data("%PDF".utf8))
            else {
                skippedFiles.append(name)
                continue
            }
            guard !candidates.contains(where: { $0.fileName == name }) else { continue }
            candidates.append(LegacyImportCandidate(fileName: name, pdfData: data, customers: model.data.customers, today: model.today))
        }
        candidates.sort { $0.issueDate < $1.issueDate }
    }
}

private struct CandidateRow: View {
    @Binding var candidate: LegacyImportCandidate
    let customers: [Customer]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $candidate.isIncluded) {
                    Text(candidate.fileName).fontWeight(.semibold)
                }
                Spacer()
                if !candidate.hasText {
                    Label("PDF enthält keinen lesbaren Text", systemImage: "eye.slash").foregroundStyle(.orange)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    TextField("Rechnungsnr.", text: $candidate.numberText).frame(width: 110)
                    DatePicker("Rechnung", selection: $candidate.issueDate.asDate, displayedComponents: .date)
                    DatePicker("Leistung", selection: $candidate.serviceDate.asDate, displayedComponents: .date)
                    TextField("Betrag", value: $candidate.total, format: .currency(code: Money.currencyCode)).frame(width: 110)
                }
                GridRow {
                    TextField("Beschreibung", text: $candidate.description).gridCellColumns(2)
                    customerPicker.gridCellColumns(2)
                }
                GridRow {
                    Toggle("Bereits bezahlt", isOn: $candidate.isPaid)
                    DatePicker("am", selection: $candidate.paidOn.asDate, displayedComponents: .date)
                        .disabled(!candidate.isPaid)
                }
            }
            .disabled(!candidate.isIncluded)
            ForEach(candidate.parsed.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 8)
    }

    private var customerPicker: some View {
        Picker("Kunde", selection: $candidate.customerChoice) {
            Text("Bitte wählen").tag(LegacyImportCandidate.CustomerChoice.none)
            if let recipient = candidate.parsed.recipient, !customers.contains(where: { $0.name == recipient.name }) {
                Text("Neu anlegen: \(recipient.name)").tag(LegacyImportCandidate.CustomerChoice.new(recipient))
            }
            ForEach(customers) { customer in
                Text(customer.name).tag(LegacyImportCandidate.CustomerChoice.existing(customer.id))
            }
        }
    }
}
