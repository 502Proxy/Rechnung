import Foundation

/// Decides when the app locks itself. Contains no UI code, so it can be tested on its own.
public struct AppLockPolicy: Sendable {
    public var isEnabled: Bool
    public var idleTimeout: TimeInterval

    public init(isEnabled: Bool, idleTimeout: TimeInterval) {
        self.isEnabled = isEnabled
        self.idleTimeout = max(60, idleTimeout)
    }

    public func shouldLock(lastActivity: Date, now: Date) -> Bool {
        isEnabled && now.timeIntervalSince(lastActivity) >= idleTimeout
    }

    /// Always lock on sleep, screen lock and user switch, whatever the idle time.
    public func shouldLockOnSystemEvent() -> Bool {
        isEnabled
    }
}
