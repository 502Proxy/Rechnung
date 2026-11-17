import Foundation
import LocalAuthentication

public protocol DeviceOwnerAuthenticating: Sendable {
    /// Asks for Touch ID, Apple Watch or the user's login password.
    func authenticate(reason: String) async -> Bool
}

/// Unlocks the app with the Mac's own owner authentication.
///
/// `deviceOwnerAuthentication` falls back to the login password, so the app
/// stays usable on Macs without Touch ID. The app never stores a password of its own.
public struct LocalAuthenticator: DeviceOwnerAuthenticating {
    public init() {}

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Passwort verwenden"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Always succeeds. Only for tests and SwiftUI previews.
public struct AlwaysAuthenticated: DeviceOwnerAuthenticating {
    public init() {}
    public func authenticate(reason: String) async -> Bool { true }
}
