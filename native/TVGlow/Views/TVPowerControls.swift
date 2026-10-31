import SwiftUI

struct TVPowerControls: View {
    @ObservedObject var store: ControlStore
    @ObservedObject var remote: AppleRemoteStore

    var body: some View {
        HStack(spacing: 9) {
            Button {
                // A paired Apple TV is connected on demand, so waking through HDMI-CEC needs no extra tap.
                Task { await store.turnOnTV(appleWake: { Task { await remote.wake() } }) }
            } label: {
                Label("Turn on", systemImage: "power")
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .disabled(store.tvConnected || store.tvPowerBusy || store.tvConnecting || store.applyingBrightness || store.editingBrightness)
            .accessibilityIdentifier("tvPowerOnButton")
            .help("Wake LG over the network and, when paired, through Apple TV (HDMI-CEC).")

            Button {
                Task { await store.turnOffTV() }
            } label: {
                Label("Turn off", systemImage: "power.circle")
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .disabled(!store.tvConnected || store.tvPowerBusy || store.tvConnecting || store.applyingBrightness || store.editingBrightness)
            .accessibilityIdentifier("tvPowerOffButton")
            .help("Turn off the television using the LG connection.")
        }
        .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(GlowTheme.line))
        .foregroundStyle(GlowTheme.accent)
    }
}
