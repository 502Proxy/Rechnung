import Foundation
import UserNotifications

public protocol UserNotifying: Sendable {
    func notify(title: String, body: String) async
}

/// System notifications, for example "Rechnung 2026-015 ist bereit zur Prüfung".
/// Invoice amounts and customer names are left out on purpose, so nothing sensitive shows on the lock screen.
public struct SystemUserNotifier: UserNotifying {
    public init() {}

    public func notify(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}

public struct SilentNotifier: UserNotifying {
    public init() {}
    public func notify(title: String, body: String) async {}
}
