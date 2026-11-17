import GageCore
import SwiftUI

struct CustomersView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Customer?

    var body: some View {
        Table(model.data.customers) {
            TableColumn("Kunde") { customer in
                VStack(alignment: .leading) {
                    Text(customer.name).fontWeight(.medium)
                    Text(customer.address.lines.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            TableColumn("E-Mail für Rechnungen") { Text($0.email?.value ?? "–") }
            TableColumn("Umsatz \(String(model.today.year))") { customer in
                Text(revenue(of: customer).formatted()).monospacedDigit()
            }
            .width(min: 100, ideal: 120)
            TableColumn("") { customer in
                Button("Bearbeiten") { editing = customer }.buttonStyle(.borderless)
            }
            .width(90)
        }
        .overlay {
            if model.data.customers.isEmpty {
                EmptyStateView(title: "Noch keine Kunden", systemImage: "person.2", message: "Lege Kunden an, um Rechnungen zu schreiben.")
            }
        }
        .navigationTitle("Kunden")
        .toolbar {
            Button("Kunde anlegen", systemImage: "person.badge.plus") {
                editing = Customer(name: "", address: PostalAddress(street: "", postalCode: "", city: ""), email: nil)
            }
        }
        .sheet(item: $editing) { customer in
            CustomerEditor(customer: customer) { updated in
                Task { await model.saveCustomer(updated) }
            }
        }
    }

    private func revenue(of customer: Customer) -> Money {
        model.data.invoices
            .filter { $0.customerID == customer.id && $0.issuedOn?.year == model.today.year }
            .map(\.total)
            .sum()
    }
}

private struct CustomerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customer: Customer
    @State private var emailText: String
    @State private var aliasesText: String
    let onSave: (Customer) -> Void

    init(customer: Customer, onSave: @escaping (Customer) -> Void) {
        _customer = State(initialValue: customer)
        _emailText = State(initialValue: customer.email?.value ?? "")
        _aliasesText = State(initialValue: customer.aliases.joined(separator: ", "))
        self.onSave = onSave
    }

    private var emailIsValid: Bool { emailText.isEmpty || EmailAddress(emailText) != nil }
    private var canSave: Bool {
        !customer.name.trimmingCharacters(in: .whitespaces).isEmpty && customer.address.isComplete && emailIsValid
    }

    var body: some View {
        Form {
            Section("Kunde") {
                TextField("Name / Firma", text: $customer.name)
                TextField("Ansprechpartner", text: Binding(
                    get: { customer.contactPerson ?? "" },
                    set: { customer.contactPerson = $0.isEmpty ? nil : $0 }
                ))
                TextField("E-Mail für Rechnungen", text: $emailText)
                if !emailIsValid {
                    Text("Bitte gib eine gültige E-Mail-Adresse ein.").font(.caption).foregroundStyle(.red)
                }
            }
            Section("Anschrift") {
                TextField("Straße und Hausnummer", text: $customer.address.street)
                TextField("PLZ", text: $customer.address.postalCode)
                TextField("Ort", text: $customer.address.city)
            }
            Section {
                TextField("Andere Namen im Kalender", text: $aliasesText, prompt: Text("z. B. Kantine, Kantine Club"))
            } footer: {
                Text("Damit ordnet Gage Kalendertermine und Zahlungen diesem Kunden zu.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    var result = customer
                    result.email = EmailAddress(emailText)
                    result.aliases = aliasesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    onSave(result)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}
