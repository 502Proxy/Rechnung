import Foundation
import GageCore
import GageIntegrations
import GagePersistence
import GageSecurity
import GageUI

/// Result of app startup: ready, or an error the user can understand.
enum AppBootstrap {
    case ready(AppEnvironment)
    case failed(String)

    @MainActor
    static func start() -> AppBootstrap {
        do {
            return try .ready(AppEnvironment(dependencies: CompositionRoot.makeDependencies()))
        } catch {
            return .failed("Der Schlüssel für deine Daten konnte nicht aus dem Schlüsselbund geladen werden. \(error.localizedDescription)")
        }
    }
}

/// Composition root: the only place that knows the concrete implementations.
enum CompositionRoot {
    static func makeDependencies() throws -> AppDependencies {
        let secrets = KeychainSecretStore(
            service: Bundle.main.bundleIdentifier ?? "app.gage.mac",
            useDataProtectionKeychain: BuildConfiguration.usesDataProtectionKeychain
        )
        let encryptor = try DataEncryptor.loadingOrCreatingKey(in: secrets)
        let storeURL = try EncryptedFileRepository.defaultFileURL()
        let archiveURL = storeURL.deletingLastPathComponent().appending(path: "Archiv", directoryHint: .isDirectory)
        let digest = SHA256Digest()
        let bunq = BunqClient(environment: BuildConfiguration.bunqEnvironment, secrets: secrets)

        return AppDependencies(
            repository: EncryptedFileRepository(fileURL: storeURL, encryptor: encryptor),
            archive: FileInvoiceArchive(baseURL: archiveURL, digest: digest),
            gigSource: EventKitGigSource(),
            bank: BunqConnection(client: bunq, accountIBAN: nil),
            mailer: SharingServiceMailComposer(),
            notifier: SystemUserNotifier(),
            digest: digest,
            authenticator: LocalAuthenticator()
        )
    }
}

enum BuildConfiguration {
    #if DEBUG
    /// Debug builds talk to the bunq sandbox, so no real data is touched during development.
    static let bunqEnvironment = BunqEnvironment.sandbox
    /// Unsigned debug and CI builds have no keychain access group.
    static let usesDataProtectionKeychain = false
    #else
    static let bunqEnvironment = BunqEnvironment.production
    static let usesDataProtectionKeychain = true
    #endif
}

/// Holds the long-lived objects of a running app.
@MainActor
final class AppEnvironment {
    let model: AppModel
    let lock: AppLockController
    let navigation = Navigation()
    private var isRunning = false

    init(dependencies: AppDependencies) {
        model = AppModel(dependencies: dependencies)
        lock = AppLockController(
            policy: AppLockPolicy(isEnabled: true, idleTimeout: 300),
            authenticator: dependencies.authenticator
        )
    }

    /// Loads the data and refreshes calendar and bank every 15 minutes.
    func run() async {
        guard !isRunning else { return }
        isRunning = true
        lock.start()
        await model.load()
        applyLockPolicy(from: model.data.settings)

        while !Task.isCancelled {
            await model.syncCalendar()
            await model.syncBank()
            try? await Task.sleep(for: .seconds(15 * 60))
        }
    }

    func applyLockPolicy(from settings: AppSettings) {
        lock.updatePolicy(AppLockPolicy(
            isEnabled: settings.appLockEnabled,
            idleTimeout: TimeInterval(settings.autoLockAfterMinutes * 60)
        ))
    }
}
