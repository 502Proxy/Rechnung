import GageCore
import SwiftUI

public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            ProfileSettings().tabItem { Label("Absender", systemImage: "person.text.rectangle") }
            AutomationSettings().tabItem { Label("Rechnungen & Kalender", systemImage: "calendar.badge.clock") }
            SecuritySettings().tabItem { Label("Sicherheit", systemImage: "lock.shield") }
        }
        .frame(width: 560)
        .padding(.vertical, 8)
    }
}

private struct ProfileSettings: View {
    @Environment(AppModel.self) private var model
    @State private var profile = BusinessProfile.empty
    @State private var ibanText = ""
    @State private var emailText = ""

    private var ibanIsValid: Bool { ibanText.isEmpty || IBAN(ibanText) != nil }
    private var emailIsValid: Bool { emailText.isEmpty || EmailAddress(emailText) != nil }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $profile.name)
                TextField("Tätigkeit", text: $profile.tradeDescription, prompt: Text("z. B. DJ & Live-Musik"))
                TextField("Straße und Hausnummer", text: $profile.address.street)
                HStack {
                    TextField("PLZ", text: $profile.address.postalCode).frame(width: 120)
                    TextField("Ort", text: $profile.address.city)
                }
                TextField("E-Mail", text: $emailText)
                if !emailIsValid { invalidHint("Bitte gib eine gültige E-Mail-Adresse ein.") }
                TextField("Telefon", text: $profile.phone)
            } header: {
                Text("Deine Angaben")
            } footer: {
                Text("Diese Angaben stehen als Pflichtangaben nach § 14 UStG auf jeder Rechnung.")
            }
            Section("Steuer") {
                TextField("Steuernummer", text: $profile.taxNumber, prompt: Text("z. B. 43/123/45678"))
                TextField("Finanzamt", text: $profile.taxOffice)
            }
            Section("Bankverbindung") {
                TextField("Bank", text: $profile.bankName)
                TextField("IBAN", text: $ibanText)
                if !ibanIsValid { invalidHint("Die IBAN ist ungültig. Bitte prüfe die Prüfziffer.") }
                TextField("BIC", text: $profile.bic)
            }
            HStack {
                Spacer()
                Button("Sichern") {
                    var updated = profile
                    updated.iban = IBAN(ibanText)
                    updated.email = EmailAddress(emailText)
                    Task { await model.saveProfile(updated) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ibanIsValid || !emailIsValid)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            profile = model.data.profile
            ibanText = profile.iban?.formatted ?? ""
            emailText = profile.email?.value ?? ""
        }
    }

    private func invalidHint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.red)
    }
}

private struct AutomationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Rechnungen") {
                Picker("Standard-Zahlungsziel", selection: binding(\.defaultPaymentTermDays)) {
                    ForEach([7, 14, 30], id: \.self) { Text("\($0) Tage").tag($0) }
                }
                LabeledContent("Nummernkreis", value: "JJJJ-NNN, fortlaufend")
                LabeledContent("Ablage", value: "Archiv im App-Container, schreibgeschützt")
            }
            Section {
                Toggle("Rechnungen aus dem Kalender erstellen", isOn: binding(\.autoInvoice.isEnabled))
                Picker("Gig-Kalender", selection: Binding(
                    get: { model.data.settings.autoInvoice.calendarTitle },
                    set: { title in Task { await model.selectCalendar(title) } }
                )) {
                    ForEach(calendarOptions, id: \.self) { Text($0).tag($0) }
                }
                Picker("Erstellen am Folgetag um", selection: binding(\.autoInvoice.hour)) {
                    ForEach(6...20, id: \.self) { Text(String(format: "%02d:00 Uhr", $0)).tag($0) }
                }
            } header: {
                Text("Apple Kalender")
            } footer: {
                Text("""
                Gage erstellt nur Entwürfe. Gesendet wird erst, wenn du die Rechnung geprüft hast. \
                Gage liest den Kalender nur und ändert keine Termine.
                """)
            }
        }
        .formStyle(.grouped)
        .task { await model.loadCalendarTitles() }
    }

    /// All calendars on this Mac. The current setting stays selectable even if the calendar is gone.
    private var calendarOptions: [String] {
        let current = model.data.settings.autoInvoice.calendarTitle
        return model.calendarTitles.contains(current) ? model.calendarTitles : [current] + model.calendarTitles
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.data.settings[keyPath: keyPath] },
            set: { newValue in Task { await model.updateSettings { $0[keyPath: keyPath] = newValue } } }
        )
    }
}

private struct SecuritySettings: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLockController.self) private var lock

    var body: some View {
        Form {
            Section {
                Toggle("Mit Touch ID oder Passwort schützen", isOn: binding(\.appLockEnabled))
                Picker("Automatisch sperren nach", selection: binding(\.autoLockAfterMinutes)) {
                    ForEach([1, 5, 15, 30], id: \.self) { Text("\($0) Min. Inaktivität").tag($0) }
                }
                .disabled(!model.data.settings.appLockEnabled)
                Button("Jetzt sperren") { lock.lock() }
                    .disabled(!model.data.settings.appLockEnabled)
            } header: {
                Text("App-Sperre")
            } footer: {
                Text("Gage sperrt sich außerdem beim Ruhezustand, bei der Bildschirmsperre und beim Benutzerwechsel.")
            }
            Section("Datenschutz") {
                LabeledContent("Datenbank", value: "AES-256-GCM, Schlüssel im Schlüsselbund")
                LabeledContent("bunq-Zugang", value: model.data.settings.bankConnectionEnabled ? "verbunden, nur Lesezugriff" : "nicht verbunden")
                LabeledContent("Änderungsprotokoll", value: "\(model.data.auditTrail.count) Einträge, verkettet")
                if model.data.settings.bankConnectionEnabled {
                    Button("bunq-Verbindung trennen", role: .destructive) { Task { await model.disconnectBank() } }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.data.settings[keyPath: keyPath] },
            set: { newValue in Task { await model.updateSettings { $0[keyPath: keyPath] = newValue } } }
        )
    }
}
