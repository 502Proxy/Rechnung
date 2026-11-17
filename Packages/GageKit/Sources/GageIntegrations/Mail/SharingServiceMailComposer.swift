import AppKit
import Foundation
import GageCore

public enum MailComposeError: Error, Equatable, Sendable, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "Es ist kein Mail-Programm eingerichtet. Richte Apple Mail ein oder wähle ein anderes Standardprogramm für E-Mails."
    }
}

/// Opens a ready-made e-mail with the PDF attached in the user's default mail app.
///
/// This is deliberately not a silent send. The user sees every message
/// before it goes out, and Gage needs no mail password or SMTP access
/// (see docs/adr/0004).
public struct SharingServiceMailComposer: MailComposing {
    public init() {}

    @MainActor
    public func compose(_ mail: OutgoingMail) throws {
        guard let service = NSSharingService(named: .composeEmail) else { throw MailComposeError.unavailable }
        service.recipients = [mail.recipient.value]
        service.subject = mail.subject
        let items: [Any] = [mail.body, mail.attachment]
        guard service.canPerform(withItems: items) else { throw MailComposeError.unavailable }
        service.perform(withItems: items)
    }
}
