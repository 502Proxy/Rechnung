import AppKit
import GageCore
import SwiftUI

/// Everything the invoice layout needs, whether the source is a draft or an issued invoice.
public struct InvoiceDocumentModel: Sendable {
    let numberText: String
    let issueDate: LocalDate
    let serviceDate: LocalDate
    let dueDate: LocalDate
    let lineItems: [LineItem]
    let total: Money
    let note: String
    let customer: Customer?
    let profile: BusinessProfile
    let isDraft: Bool

    public init(invoice: Invoice, customer: Customer?, profile: BusinessProfile, isDraft: Bool) {
        numberText = invoice.number.description
        issueDate = invoice.issueDate
        serviceDate = invoice.serviceDate
        dueDate = invoice.dueDate
        lineItems = invoice.lineItems
        total = invoice.total
        note = invoice.note
        self.customer = customer
        self.profile = profile
        self.isDraft = isDraft
    }

    public init(draft: InvoiceDraft, number: InvoiceNumber?, customer: Customer?, profile: BusinessProfile) {
        numberText = number?.description ?? "wird vergeben"
        issueDate = draft.issueDate
        serviceDate = draft.serviceDate
        dueDate = draft.dueDate
        lineItems = draft.lineItems
        total = draft.total
        note = draft.note
        self.customer = customer
        self.profile = profile
        isDraft = true
    }
}

/// An A4 invoice with every mandatory field under § 14 UStG and the § 19 UStG note.
struct InvoiceDocumentView: View {
    static let pageSize = CGSize(width: 595, height: 842) // A4 in points

    let model: InvoiceDocumentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            addressBlock.padding(.top, 28)
            Text("Rechnung").font(.system(size: 18, weight: .bold)).padding(.top, 26)
            Text("Vielen Dank für die Zusammenarbeit. Ich berechne Ihnen folgende Leistungen:")
                .foregroundStyle(Color(white: 0.4))
                .padding(.top, 4)
            itemsTable.padding(.top, 14)
            totals.padding(.top, 10)
            Text("Gemäß § 19 UStG wird keine Umsatzsteuer berechnet (Kleinunternehmerregelung).")
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.95))
                .padding(.top, 16)
            if !model.note.isEmpty {
                Text(model.note).padding(.top, 12)
            }
            Text("Bitte überweisen Sie den Betrag bis zum \(model.dueDate.germanFormatted) unter Angabe der Rechnungsnummer \(model.numberText).")
                .padding(.top, 12)
            Spacer(minLength: 0)
            footer
        }
        .font(.system(size: 9.5))
        .foregroundStyle(Color(white: 0.1))
        .padding(.horizontal, 48)
        .padding(.vertical, 44)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .overlay(alignment: .topTrailing) {
            if model.isDraft {
                Text("ENTWURF")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(16)
            }
        }
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.profile.name).font(.system(size: 14, weight: .bold))
                Text(model.profile.tradeDescription).foregroundStyle(Color(white: 0.4))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                ForEach(model.profile.address.lines, id: \.self) { Text($0) }
                if let email = model.profile.email { Text(email.value) }
                if !model.profile.phone.isEmpty { Text(model.profile.phone) }
            }
            .font(.system(size: 8))
            .foregroundStyle(Color(white: 0.35))
        }
    }

    private var addressBlock: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                Text(([model.profile.name] + model.profile.address.lines).joined(separator: " · "))
                    .font(.system(size: 7))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.bottom, 6)
                if let customer = model.customer {
                    Text(customer.name).bold()
                    if let contact = customer.contactPerson, !contact.isEmpty { Text(contact) }
                    ForEach(customer.address.lines, id: \.self) { Text($0) }
                } else {
                    Text("Kunde fehlt").foregroundStyle(.red)
                }
            }
            Spacer()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 1) {
                metaRow("Rechnungsnr.", model.numberText, bold: true)
                metaRow("Rechnungsdatum", model.issueDate.germanFormatted)
                metaRow("Leistungsdatum", model.serviceDate.germanFormatted)
                metaRow("Zahlbar bis", model.dueDate.germanFormatted)
            }
            .font(.system(size: 8.5))
        }
    }

    private func metaRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(Color(white: 0.4))
            Text(value).fontWeight(bold ? .semibold : .regular).monospacedDigit()
        }
    }

    private var itemsTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text("Pos.")
                Text("Leistung").gridColumnAlignment(.leading)
                Text("Menge").gridColumnAlignment(.trailing)
                Text("Einzelpreis").gridColumnAlignment(.trailing)
                Text("Gesamt").gridColumnAlignment(.trailing)
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Color(white: 0.4))
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(model.lineItems.enumerated()), id: \.element.id) { index, item in
                GridRow {
                    Text("\(index + 1)")
                    Text(item.description).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(item.quantity.formatted()) \(item.unit.displayName)")
                    Text(item.unitPrice.formatted())
                    Text(item.total.formatted())
                }
                .monospacedDigit()
            }
        }
    }

    private var totals: some View {
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 3) {
            GridRow { Text("Zwischensumme"); Text(model.total.formatted()) }
            GridRow { Text("Umsatzsteuer"); Text(Money.zero.formatted()) }
            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text("Rechnungsbetrag").bold()
                Text(model.total.formatted()).bold()
            }
            .font(.system(size: 11))
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.profile.name)
                    ForEach(model.profile.address.lines, id: \.self) { Text($0) }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bankverbindung: \(model.profile.bankName)")
                    Text("IBAN \(model.profile.iban?.formatted ?? "–")")
                    if !model.profile.bic.isEmpty { Text("BIC \(model.profile.bic)") }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Steuernummer \(model.profile.taxNumber)")
                    Text(model.profile.taxOffice)
                }
            }
            .font(.system(size: 7.5))
            .foregroundStyle(Color(white: 0.4))
        }
    }
}

/// Renders the invoice layout to a vector PDF (A4, one page).
@MainActor
enum InvoicePDFRenderer {
    enum RenderError: Error, LocalizedError {
        case contextUnavailable
        var errorDescription: String? { "Die PDF-Datei konnte nicht erzeugt werden." }
    }

    static func render(_ model: InvoiceDocumentModel) throws -> Data {
        let renderer = ImageRenderer(content: InvoiceDocumentView(model: model))
        renderer.proposedSize = ProposedViewSize(InvoiceDocumentView.pageSize)

        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: InvoiceDocumentView.pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "Rechnung \(model.numberText)",
            kCGPDFContextAuthor: model.profile.name,
            kCGPDFContextCreator: "Gage",
        ]
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { throw RenderError.contextUnavailable }

        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }
}
