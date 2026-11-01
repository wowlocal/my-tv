import AppIntents
import Foundation

extension Notification.Name {
    /// Posted in the app when something outside it (Control Center, Shortcuts) asks for the remote.
    static let showRemote = Notification.Name("com.anna.tvglow.showRemote")
}

/// Brings TV Glow to the front on its remote, like Apple's Remote control in Control Center.
/// Compiled into the app and the TVGlowControls extension: the control runs it in the app.
/// It only opens the remote; reconnecting on the way in reads devices and sends no commands.
struct OpenRemoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Remote"
    static let description = IntentDescription("Opens the TV Glow remote for your Apple TV.")

    /// iOS 17–25 and macOS 14–25. Newer systems read `supportedModes`.
    static let openAppWhenRun = true

    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .showRemote, object: nil)
        return .result()
    }
}
