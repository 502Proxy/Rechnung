import AppKit
import Foundation
import GageSecurity
import Observation

/// Locks the app at launch, after inactivity, on sleep and on screen lock.
/// Unlocking uses Touch ID or the Mac's login password.
@MainActor
@Observable
public final class AppLockController {
    public private(set) var isLocked: Bool
    public private(set) var isAuthenticating = false

    @ObservationIgnored private var policy: AppLockPolicy
    @ObservationIgnored private var lastActivity = Date()
    private let authenticator: any DeviceOwnerAuthenticating
    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Timer?

    public init(policy: AppLockPolicy, authenticator: any DeviceOwnerAuthenticating) {
        self.policy = policy
        self.authenticator = authenticator
        isLocked = policy.isEnabled
    }

    public func updatePolicy(_ policy: AppLockPolicy) {
        self.policy = policy
        if !policy.isEnabled { isLocked = false }
    }

    public func lock() {
        guard policy.isEnabled else { return }
        isLocked = true
    }

    public func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await authenticator.authenticate(reason: "Gage entsperren, um deine Rechnungen anzuzeigen") {
            isLocked = false
            lastActivity = Date()
        }
    }

    /// Starts watching user activity and system events. Call once at launch.
    public func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.lastActivity = Date() }
            return event
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let systemEvents: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")),
        ]
        for (center, name) in systemEvents {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.policy.shouldLockOnSystemEvent() else { return }
                    self.lock()
                }
            })
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.policy.shouldLock(lastActivity: self.lastActivity, now: Date()) else { return }
                self.lock()
            }
        }
    }
}
