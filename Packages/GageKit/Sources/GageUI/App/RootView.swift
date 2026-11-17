import GageCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case invoices
    case customers
    case gigs
    case bank
    case taxReport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Übersicht"
        case .invoices: "Rechnungen"
        case .customers: "Kunden"
        case .gigs: "Gigs & Kalender"
        case .bank: "bunq Konto"
        case .taxReport: "Gewinnermittlung (EÜR)"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "house"
        case .invoices: "doc.text"
        case .customers: "person.2"
        case .gigs: "calendar"
        case .bank: "building.columns"
        case .taxReport: "chart.bar.xaxis"
        }
    }
}

/// Holds which sheet is open, so menu commands and views can open the editor.
@MainActor
@Observable
public final class Navigation {
    var selection: SidebarItem? = .dashboard
    var editor: EditorRequest?

    public init() {}

    public func newInvoice() { editor = EditorRequest(invoiceID: nil, gig: nil) }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    let invoiceID: UUID?
    let gig: Gig?
}

public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLockController.self) private var lock
    @Environment(Navigation.self) private var navigation

    public init() {}

    public var body: some View {
        @Bindable var navigation = navigation
        ZStack {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
            .disabled(lock.isLocked)
            .blur(radius: lock.isLocked ? 24 : 0)
            .accessibilityHidden(lock.isLocked)

            if lock.isLocked {
                LockView()
            }
        }
        .sheet(item: $navigation.editor) { request in
            InvoiceEditorView(request: request)
        }
        .alert(
            "Hinweis",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
            presenting: model.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .overlay(alignment: .bottom) {
            if let info = model.infoMessage {
                Label(info, systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: info) {
                        try? await Task.sleep(for: .seconds(4))
                        model.infoMessage = nil
                    }
            }
        }
        .animation(.default, value: model.infoMessage)
        .tint(Theme.accent)
    }

    private var sidebar: some View {
        @Bindable var navigation = navigation
        return List(selection: $navigation.selection) {
            Section {
                row(.dashboard)
                row(.invoices, badge: model.invoices(in: .overdue).count + model.invoices(in: .draft).count)
                row(.customers)
            }
            Section("Automatisierung") {
                row(.gigs)
                row(.bank, badge: model.transactionsNeedingReview.count)
            }
            Section("Finanzamt") {
                row(.taxReport)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        .safeAreaInset(edge: .bottom) {
            Label("Daten lokal verschlüsselt", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .badge(badge)
            .tag(item)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection ?? .dashboard {
        case .dashboard: DashboardView()
        case .invoices: InvoicesView()
        case .customers: CustomersView()
        case .gigs: GigsView()
        case .bank: BankView()
        case .taxReport: TaxReportView()
        }
    }
}

struct LockView: View {
    @Environment(AppLockController.self) private var lock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("Gage ist gesperrt").font(.title2.weight(.semibold))
            Text("Entsperre mit Touch ID oder deinem Mac-Passwort.")
                .foregroundStyle(.secondary)
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Entsperren", systemImage: "touchid")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(lock.isAuthenticating)
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .task { await lock.unlock() }
    }
}
