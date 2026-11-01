import AppIntents
import Foundation

extension Notification.Name {
    /// Posted in the app when the TV Power control (Action button, Control Center) is pressed.
    static let togglePower = Notification.Name("com.anna.tvglow.togglePower")
}

/// A TV Power press from outside the app, waiting for the remote to act on it. The intent can run
/// before the remote's screen exists (cold launch), so the press is kept until the screen takes it.
@MainActor
enum PendingRemoteActions {
    private(set) static var powerToggle = false

    static func requestPowerToggle() {
        powerToggle = true
        NotificationCenter.default.post(name: .togglePower, object: nil)
    }

    /// Returns true once per press.
    static func takePowerToggle() -> Bool {
        defer { powerToggle = false }
        return powerToggle
    }
}

/// Turns the TV off when it's on, and on when it's off, like the remote's power button. Opens
/// TV Glow to do it: the TV pairing and the device connections live in the app. Compiled into the
/// app and the TVGlowControls extension; the control runs it in the app.
struct TogglePowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn TV On or Off"
    static let description = IntentDescription("Turns the LG TV off if it's on, or on through Apple TV if it's off.")

    /// iOS 17–25 and macOS 14–25. Newer systems read `supportedModes`.
    static let openAppWhenRun = true

    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRemoteActions.requestPowerToggle()
        return .result()
    }
}
