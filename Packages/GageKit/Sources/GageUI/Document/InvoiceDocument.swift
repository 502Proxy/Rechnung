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
        numberText = number?.description ?? "–"
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
///
/// The layout follows the invoices Gage users created in Pages: Courier New,
/// black and white, sender in four columns, a ruled table and a payment note.
struct InvoiceDocumentView: View {
    static let pageSize = CGSize(width: 595, height: 842) // A4 in points

    let model: InvoiceDocumentModel

    private static let ink = Color(white: 0.08)
    private static let rule = Color(white: 0.1)
    private static let columns = (date: CGFloat(68), number: CGFloat(68), quantity: CGFloat(52), price: CGFloat(58), cost: CGFloat(70))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let logo = model.profile.logoPNG.flatMap(NSImage.init(data:)) {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 64, maxHeight: 64, alignment: .leading)
                    .padding(.top, 12)
            }
            recipient.padding(.top, 26)
            table.padding(.top, 54)
            Spacer(minLength: 16)
            totals
        }
        .font(Self.text(8.5))
        .foregroundStyle(Self.ink)
        .padding(.horizontal, 40)
        .padding(.top, 36)
        .padding(.bottom, 44)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .overlay(alignment: .topTrailing) {
            if model.isDraft {
                Text("ENTWURF")
                    .font(Self.text(9, bold: true))
                    .foregroundStyle(.orange)
                    .padding(12)
            }
        }
        .environment(\.colorScheme, .light)
    }

    static func text(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom("Courier New", size: size).weight(bold ? .bold : .regular)
    }

    // MARK: Sections

    private var header: some View {
        let profile = model.profile
        let title = profile.artistName.isEmpty ? profile.name : profile.artistName
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Self.text(8.5, bold: true))
                if !profile.taxNumber.isEmpty { Text(profile.taxNumber).font(Self.text(8.5, bold: true)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(profile.name.split(separator: " ").map(String.init), id: \.self) { Text($0) }
            }
            .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                if !profile.phone.isEmpty { Text(profile.phone) }
                if let email = profile.email { Text(email.value) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(profile.address.lines, id: \.self) { Text($0) }
                Text("Deutschland")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recipient: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let customer = model.customer {
                Text(customer.name)
                if let contact = customer.contactPerson, !contact.isEmpty { Text(contact) }
                ForEach(customer.address.lines, id: \.self) { Text($0) }
            } else {
                Text("Kunde fehlt").foregroundStyle(.red)
            }
        }
    }

    private var table: some View {
        let widths = Self.columns
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Self.rule).frame(height: 1)
            HStack(alignment: .top, spacing: 6) {
                Text("RECHNUNGS-\nDATUM").frame(width: widths.date, alignment: .leading)
                Text("RECHNUNGS-\nNUMMER").frame(width: widths.number, alignment: .leading)
                Text("BESCHREIBUNG").frame(maxWidth: .infinity, alignment: .leading)
                Text("MENGE").frame(width: widths.quantity, alignment: .leading)
                Text("PREIS/H").frame(width: widths.price, alignment: .trailing)
                Text("KOSTEN").frame(width: widths.cost, alignment: .trailing)
            }
            .font(Self.text(8, bold: true))
            .padding(.vertical, 6)
            Rectangle().fill(Self.rule).frame(height: 0.5)

            ForEach(Array(model.lineItems.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    Text(index == 0 ? short(model.issueDate) : "").frame(width: widths.date, alignment: .leading)
                    Text(index == 0 ? model.numberText : "").frame(width: widths.number, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.description)
                        if index == 0 {
                            Text("Leistungsdatum: \(short(model.serviceDate))").foregroundStyle(Color(white: 0.4))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.unit == .flatRate ? "" : "\(item.quantity.formatted()) \(item.unit == .hour ? "h" : item.unit.displayName)")
                        .frame(width: widths.quantity, alignment: .leading)
                    Text(item.unit == .flatRate ? "" : item.unitPrice.formatted()).frame(width: widths.price, alignment: .trailing)
                    Text(item.total.formatted()).frame(width: widths.cost, alignment: .trailing)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var totals: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer().frame(width: Self.columns.date + Self.columns.number + 12)
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Self.rule).frame(height: 0.5)
                amountRow("ZWISCHENSUMME", model.total, bold: true)
                Rectangle().fill(Self.rule).frame(height: 0.5)
                Text("Gemäß § 19 UStG wird keine Umsatzsteuer berechnet.")
                    .foregroundStyle(Color(white: 0.35))
                    .padding(.vertical, 8)
                if !model.note.isEmpty {
                    Text(model.note).padding(.bottom, 8)
                }
                Rectangle().fill(Self.rule).frame(height: 1)
                amountRow("SUMME", model.total, bold: true)
                Rectangle().fill(Self.rule).frame(height: 1)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Zahlungshinweis:").font(Self.text(8.5, bold: true))
                        Text("Bitte überweisen Sie den Rechnungsbetrag bis zum \(short(model.dueDate)) auf folgendes Konto:")
                            .foregroundStyle(Color(white: 0.35))
                    }
                    .frame(width: 130, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.profile.name.uppercased())
                        Text(model.profile.iban?.electronicFormat ?? "IBAN fehlt")
                        if !model.profile.bic.isEmpty { Text(model.profile.bic) }
                        Text(model.profile.bankName)
                    }
                    .font(Self.text(8.5, bold: true))
                }
                .padding(.vertical, 10)
                Rectangle().fill(Self.rule).frame(height: 0.5)
            }
        }
    }

    private func amountRow(_ title: String, _ amount: Money, bold: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(amount.formatted()).monospacedDigit()
        }
        .font(Self.text(8.5, bold: bold))
        .padding(.vertical, 7)
    }

    /// "10.11.26", as on the earlier invoices.
    private func short(_ date: LocalDate) -> String {
        String(format: "%02d.%02d.%02d", date.day, date.month, date.year % 100)
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
