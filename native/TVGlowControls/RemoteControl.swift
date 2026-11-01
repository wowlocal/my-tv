import AppIntents
import SwiftUI
import WidgetKit

@main
struct TVGlowControls: WidgetBundle {
    var body: some Widget {
        RemoteControl()
        PowerControl()
    }
}

/// A Control Center (and Lock Screen / Action button) control that opens the TV Glow remote,
/// in place of Apple's own Apple TV Remote control.
struct RemoteControl: ControlWidget {
    static let kind = "com.anna.tvglow.remote"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenRemoteIntent()) {
                Label("TV Glow Remote", systemImage: "appletvremote.gen4.fill")
            }
        }
        .displayName("TV Glow Remote")
        .description("Opens the TV Glow remote for your Apple TV.")
    }
}

/// Turns the TV on or off, like the remote's power button. Meant for the Action button
/// (Settings → Action Button → Controls) or Control Center.
struct PowerControl: ControlWidget {
    static let kind = "com.anna.tvglow.power"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TogglePowerIntent()) {
                Label("TV Power", systemImage: "power")
            }
        }
        .displayName("TV Power")
        .description("Turns the TV off if it's on, or on if it's off.")
    }
}
