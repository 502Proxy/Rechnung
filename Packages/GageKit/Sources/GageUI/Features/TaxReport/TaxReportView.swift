import Charts
import GageCore
import SwiftUI
import UniformTypeIdentifiers

struct TaxReportView: View {
    @Environment(AppModel.self) private var model
    @State private var year: Int?
    @State private var exportDocument: CSVDocument?

    var body: some View {
        let selectedYear = year ?? model.today.year
        let report = model.report(year: selectedYear)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if report.unreviewedTransactionCount > 0 {
                    Label(
                        "\(report.unreviewedTransactionCount) Buchung(en) sind noch nicht zugeordnet und fehlen in der Aufstellung.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    KPITile(title: "Betriebseinnahmen", value: report.income.formatted(), footnote: "umsatzsteuerfrei nach § 19 UStG")
                    KPITile(title: "Betriebsausgaben", value: report.totalExpenses.formatted(), footnote: "\(ExpenseCategory.allCases.count) Kategorien")
                    KPITile(title: "Gewinn", value: report.profit.formatted(), footnote: "für die Einkommensteuererklärung", tone: Theme.accent)
                }
                HStack(alignment: .top, spacing: Theme.spacing) {
                    GroupBox("Monatsverlauf") { chart(report).frame(height: 240).padding(.top, 8) }
                        .frame(maxWidth: .infinity)
                    GroupBox("Aufstellung") { breakdown(report) }
                        .frame(width: 340)
                }
                Text("Einnahmen zählen in dem Jahr, in dem das Geld eingeht (§ 11 EStG). Übertrage die Werte in die Anlage EÜR in ELSTER. Gage ersetzt keine Steuerberatung.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("Gewinnermittlung \(String(selectedYear))")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Jahr", selection: Binding(get: { selectedYear }, set: { year = $0 })) {
                    ForEach((model.today.year - 4)...model.today.year, id: \.self) { Text(String($0)).tag($0) }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("CSV exportieren", systemImage: "square.and.arrow.up") {
                    exportDocument = CSVDocument(text: ProfitReportCalculator().csv(for: report))
                }
            }
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "EUER_\(selectedYear).csv"
        ) { result in
            if case let .failure(error) = result { model.errorMessage = error.localizedDescription }
        }
    }

    private func chart(_ report: ProfitReport) -> some View {
        Chart {
            ForEach(report.monthly) { month in
                BarMark(x: .value("Monat", monthName(month.month)), y: .value("Betrag", NSDecimalNumber(decimal: month.income.decimalValue).doubleValue))
                    .foregroundStyle(by: .value("Art", "Einnahmen"))
                    .position(by: .value("Art", "Einnahmen"))
                BarMark(x: .value("Monat", monthName(month.month)), y: .value("Betrag", NSDecimalNumber(decimal: month.expenses.decimalValue).doubleValue))
                    .foregroundStyle(by: .value("Art", "Ausgaben"))
                    .position(by: .value("Art", "Ausgaben"))
            }
        }
        .chartForegroundStyleScale(["Einnahmen": Theme.accent, "Ausgaben": Color.orange.opacity(0.75)])
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.formatted(.currency(code: Money.currencyCode).precision(.fractionLength(0))))
                    }
                }
            }
        }
        .accessibilityLabel("Einnahmen und Ausgaben je Monat")
    }

    private func breakdown(_ report: ProfitReport) -> some View {
        VStack(spacing: 6) {
            row("Betriebseinnahmen", report.income, bold: true)
            Divider()
            ForEach(ExpenseCategory.allCases) { category in
                row(category.displayName, report.expensesByCategory[category] ?? .zero)
            }
            Divider()
            row("Summe Ausgaben", -report.totalExpenses, bold: true)
            Divider()
            row("Gewinn", report.profit, bold: true).font(.title3)
        }
        .padding(.top, 6)
    }

    private func row(_ title: String, _ amount: Money, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(amount.formatted()).monospacedDigit()
        }
        .fontWeight(bold ? .semibold : .regular)
    }

    private func monthName(_ month: Int) -> String {
        Calendar(identifier: .gregorian).shortMonthSymbols[month - 1]
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // UTF-8 with BOM so Excel shows umlauts correctly.
        FileWrapper(regularFileWithContents: Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8))
    }
}
