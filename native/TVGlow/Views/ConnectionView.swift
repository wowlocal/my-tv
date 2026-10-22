import SwiftUI

struct ConnectionView: View {
    @ObservedObject var store: ControlStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Connections").font(.system(size: 23, weight: .semibold))
                    Text("Television & soundbar").font(.system(size: 12)).foregroundStyle(GlowTheme.muted)
                }
                Spacer()
                RoundControl(symbol: "xmark", label: "Close connections") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 9) {
                Label("LG C1 television", systemImage: "tv").font(.system(size: 13, weight: .medium))
                TextField("TV IP address", text: $store.tvAddress).textFieldStyle(.roundedBorder)
                    .disabled(store.tvConnecting || store.tvPowerBusy).accessibilityIdentifier("tvAddressField")
                TextField("TV MAC address for wake", text: $store.tvMAC).textFieldStyle(.roundedBorder)
                    .disabled(store.tvPowerBusy).accessibilityIdentifier("tvMACField")
                Toggle("Also wake connected Apple TV (HDMI-CEC)", isOn: $store.wakeWithAppleTV)
                    .font(.system(size: 11)).disabled(store.tvPowerBusy)
                Text("Turn on uses the TV’s wired MAC address. Enable TV On with Mobile in LG settings. Apple TV wake requires HDMI-CEC / Simplink on the TV.")
                    .font(.system(size: 10)).foregroundStyle(GlowTheme.muted).fixedSize(horizontal: false, vertical: true)
                Text("Choose Accept on the TV when pairing for the first time. Pairing is saved securely on this device.")
                    .font(.system(size: 11)).foregroundStyle(GlowTheme.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(store.tvConnecting ? "Connecting…" : "Connect TV") { Task { await store.connectTV() } }
                        .disabled(store.tvConnecting || store.applyingBrightness || store.tvPowerBusy)
                    Spacer()
                    Button("Forget pairing") { store.forgetTV() }.buttonStyle(.plain).foregroundStyle(GlowTheme.muted)
                        .disabled(store.tvConnecting || store.applyingBrightness || store.tvPowerBusy)
                }
                Text(store.tvMessage).font(.system(size: 11)).foregroundStyle(store.tvError ? .orange : GlowTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(GlowTheme.line)
            VStack(alignment: .leading, spacing: 9) {
                Label("Sonos soundbar", systemImage: "hifispeaker").font(.system(size: 13, weight: .medium))
                TextField("Sonos IP address", text: $store.sonosAddress).textFieldStyle(.roundedBorder)
                    .disabled(store.sonosConnecting).accessibilityIdentifier("sonosAddressField")
                Button(store.sonosConnecting ? "Connecting…" : "Connect Sonos") { Task { await store.connectSonos() } }
                    .disabled(store.sonosConnecting || store.applyingVolume)
                Text(store.sonosMessage).font(.system(size: 11)).foregroundStyle(store.sonosError ? .orange : GlowTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Connect to the home network that can reach both devices. No Mac server is needed.")
                .font(.system(size: 11)).foregroundStyle(GlowTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28).frame(idealWidth: 420)
        .background(GlowTheme.background).foregroundStyle(GlowTheme.ink).tint(GlowTheme.accent).preferredColorScheme(.dark)
    }
}
