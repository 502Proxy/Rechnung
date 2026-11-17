import Foundation
import GageCore
import GageSecurity

/// Every external dependency of the UI in one place.
///
/// The app target wires up the real implementations (composition root).
/// Tests and previews use in-memory replacements.
public struct AppDependencies: Sendable {
    public var repository: any AppDataRepository
    public var archive: any InvoiceArchive
    public var gigSource: any GigSource
    public var bank: any BankConnecting
    public var mailer: any MailComposing
    public var notifier: any UserNotifying
    public var digest: any DigestProviding
    public var authenticator: any DeviceOwnerAuthenticating
    public var now: @Sendable () -> Date

    public init(
        repository: any AppDataRepository,
        archive: any InvoiceArchive,
        gigSource: any GigSource,
        bank: any BankConnecting,
        mailer: any MailComposing,
        notifier: any UserNotifying,
        digest: any DigestProviding,
        authenticator: any DeviceOwnerAuthenticating,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.archive = archive
        self.gigSource = gigSource
        self.bank = bank
        self.mailer = mailer
        self.notifier = notifier
        self.digest = digest
        self.authenticator = authenticator
        self.now = now
    }
}
