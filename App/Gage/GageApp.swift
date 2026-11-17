import GageCore
import GageSecurity
import GageUI
import SwiftUI

@main
struct GageApp: App {
    @State private var bootstrap = AppBootstrap.start()

    var body: some Scene {
        Window("Gage", id: "main") {
            switch bootstrap {
            case let .ready(environment):
                MainWindow(environment: environment)
            case let .failed(message):
                StartupErrorView(message: message)
            }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            if case let .ready(environment) = bootstrap {
                CommandGroup(replacing: .newItem) {
                    Button("Neue Rechnung") { environment.navigation.newInvoice() }
                        .keyboardShortcut("n")
                }
                CommandGroup(after: .appSettings) {
                    Button("Gage sperren") { environment.lock.lock() }
                        .keyboardShortcut("l", modifiers: [.command, .control])
                }
            }
        }

        Settings {
            if case let .ready(environment) = bootstrap {
                SettingsView()
                    .environment(environment.model)
                    .environment(environment.lock)
                    .disabled(environment.lock.isLocked)
            }
        }
    }
}

private struct MainWindow: View {
    let environment: AppEnvironment

    var body: some View {
        RootView()
            .environment(environment.model)
            .environment(environment.lock)
            .environment(environment.navigation)
            .frame(minWidth: 1100, minHeight: 700)
            .task { await environment.run() }
            .onChange(of: environment.model.data.settings) { _, settings in
                environment.applyLockPolicy(from: settings)
            }
    }
}

private struct StartupErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Gage konnte nicht starten", systemImage: "exclamationmark.lock")
        } description: {
            Text(message)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
