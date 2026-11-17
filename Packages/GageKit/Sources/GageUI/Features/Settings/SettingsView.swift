import AppKit
import GageCore
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showsLogoPicker = false
    @State private var logoError: String?

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
            Section {
                TextField("Künstlername / Projekt", text: $profile.artistName, prompt: Text("z. B. Prysma/Takttornado"))
                HStack(spacing: 12) {
                    if let logo = profile.logoPNG.flatMap(NSImage.init(data:)) {
                        Image(nsImage: logo).resizable().scaledToFit().frame(width: 48, height: 48)
                    }
                    Button(profile.logoPNG == nil ? "Logo auswählen …" : "Logo ersetzen …") { showsLogoPicker = true }
                    if profile.logoPNG != nil {
                        Button("Entfernen", role: .destructive) { profile.logoPNG = nil }
                    }
                }
                if let logoError { invalidHint(logoError) }
            } header: {
                Text("Auftritt auf der Rechnung")
            } footer: {
                Text("Steht oben links auf jeder Rechnung. Das Logo wird verkleinert und ohne Metadaten gespeichert.")
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
        .fileImporter(isPresented: $showsLogoPicker, allowedContentTypes: [.png, .jpeg, .heic, .tiff]) { result in
            guard case let .success(url) = result else { return }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), data.count <= 5 * 1024 * 1024, let png = LogoImage.normalizedPNG(from: data) {
                profile.logoPNG = png
                logoError = nil
            } else {
                logoError = "Das Bild konnte nicht verwendet werden. Bitte wähle eine PNG- oder JPEG-Datei bis 5 MB."
            }
        }
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
                Picker("Rechnungsnummern", selection: binding(\.numberScheme)) {
                    ForEach(InvoiceNumberScheme.allCases) { Text($0.displayName).tag($0) }
                }
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

/// Scales a logo to at most 600 px and re-encodes it as PNG. Re-encoding drops EXIF and other metadata.
enum LogoImage {
    static func normalizedPNG(from data: Data, maximumSide: CGFloat = 600) -> Data? {
        guard let source = NSBitmapImageRep(data: data), source.pixelsWide > 0, source.pixelsHigh > 0 else { return nil }
        let scale = min(1, maximumSide / CGFloat(max(source.pixelsWide, source.pixelsHigh)))
        let width = Int(CGFloat(source.pixelsWide) * scale)
        let height = Int(CGFloat(source.pixelsHigh) * scale)
        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: target) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return target.representation(using: .png, properties: [:])
    }
}
