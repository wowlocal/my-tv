import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ControlStore
    @ObservedObject var remote: AppleRemoteStore
    @State private var showingConnections = false
    @State private var showingDevices = false
    @State private var showingKeyboard = false
    @State private var showingPower = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                AppleRemoteCard(remote: remote, showDevices: { showingDevices = true })
                VStack(spacing: 0) {
                    VolumeCard(store: store)
                    Rectangle().fill(GlowTheme.line).frame(height: 1).padding(.horizontal, 20)
                    BrightnessCard(store: store)
                }
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                footer
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 20)
            .frame(maxWidth: 460).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background {
            LinearGradient(colors: [Color(white: 0.105), GlowTheme.background, Color(white: 0.035)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        }
        .foregroundStyle(GlowTheme.ink).tint(GlowTheme.accent).preferredColorScheme(.dark)
        .sheet(isPresented: $showingConnections) { ConnectionView(store: store) }
        .task { store.start(); remote.start() }
        .onChange(of: remote.connected) { _, connected in
            if connected { showingDevices = false }
            else { showingKeyboard = false }
        }
    }

    private var deviceName: String {
        remote.snapshot.connectedName ?? remote.snapshot.devices.first(where: { $0.id == remote.selectedDeviceID })?.name ?? "Apple TV"
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundControl(symbol: "keyboard", label: "Apple TV keyboard", size: 42) { showingKeyboard = true }
                .disabled(!remote.connected)
                .opacity(remote.connected ? 1 : 0.4)
                .accessibilityIdentifier("appleTVKeyboardButton")
                .popover(isPresented: $showingKeyboard) {
                    AppleTVKeyboardView(remote: remote).frame(width: 310).padding(22)
                        .presentationCompactAdaptation(.popover)
                }
            Spacer(minLength: 0)
            Button { showingDevices = true } label: {
                VStack(spacing: 5) {
                    Text("Living Room").font(.system(size: 11, weight: .medium)).foregroundStyle(GlowTheme.muted)
                    HStack(spacing: 7) {
                        Text(deviceName).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(GlowTheme.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Choose Apple TV, \(deviceName)")
            .accessibilityIdentifier("appleTVDeviceSelector")
            .popover(isPresented: $showingDevices) {
                AppleTVConnectionView(remote: remote).frame(width: 310).padding(22)
                    .presentationCompactAdaptation(.popover)
            }
            Spacer(minLength: 0)
            RoundControl(symbol: "power", label: "TV power", size: 42) { showingPower = true }
                .accessibilityIdentifier("tvPowerMenuButton")
                .popover(isPresented: $showingPower) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label("LG C1", systemImage: "tv").font(.system(size: 16, weight: .semibold))
                            Spacer()
                            ConnectionBadge(connected: store.tvConnected, busy: store.tvPowerBusy || store.tvConnecting)
                        }
                        TVPowerControls(store: store, remote: remote)
                        DeviceMessage(text: store.tvMessage, error: store.tvError)
                    }
                    .padding(22).frame(width: 330).presentationCompactAdaptation(.popover)
                }
        }
    }

    private var footer: some View {
        HStack {
            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "TV Glow")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(GlowTheme.muted)
            Spacer()
            Button { showingConnections = true } label: {
                Label("Connections", systemImage: "slider.horizontal.3").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(GlowTheme.muted).accessibilityIdentifier("connectionsButton")
        }
        .padding(.horizontal, 5)
    }
}

struct BrightnessCard: View {
    @ObservedObject var store: ControlStore
    @State private var showingPresets = false

    private var available: Bool { store.tvConnected && !store.applyingBrightness && !store.tvPowerBusy }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { showingPresets = true } label: {
                    HStack(spacing: 5) {
                        Text("Brightness")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                }
                .buttonStyle(.plain).accessibilityLabel("Brightness presets").accessibilityIdentifier("brightnessPresetsButton")
                .popover(isPresented: $showingPresets) { presets.presentationCompactAdaptation(.popover) }
                Spacer()
                if store.tvConnected {
                    Text("\(Int(store.brightnessDraft))%")
                        .monospacedDigit().accessibilityLabel("Brightness \(Int(store.brightnessDraft)) percent")
                } else {
                    Button(store.tvConnecting ? "Connecting…" : "Connect TV") { Task { await store.connectTV() } }
                        .buttonStyle(.plain).disabled(store.tvConnecting || store.tvPowerBusy)
                        .help(store.tvMessage).accessibilityIdentifier("connectTVButton")
                }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(GlowTheme.muted)
            HStack(spacing: 14) {
                adjustment("sun.min", label: "Dim brightness by 5") { set(max(0, Int(store.brightnessDraft) - 5)) }
                Slider(value: $store.brightnessDraft, in: 0...100) { editing in
                    store.editingBrightness = editing
                    if !editing { set(Int(store.brightnessDraft)) }
                }
                .accessibilityLabel("TV brightness").accessibilityValue("\(Int(store.brightnessDraft)) percent")
                .accessibilityIdentifier("brightnessSlider")
                adjustment("sun.max.fill", label: "Increase brightness by 5") { set(min(100, Int(store.brightnessDraft) + 5)) }
            }
            .disabled(!available).opacity(store.tvConnected ? 1 : 0.35)
            if store.tvError && store.tvConnected {
                DeviceMessage(text: store.tvMessage, error: true).accessibilityIdentifier("tvMessage")
            }
        }
        .padding(18)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OLED brightness").font(.system(size: 16, weight: .semibold))
            HStack(spacing: 10) {
                preset("Night", symbol: "moon", value: 15)
                preset("Everyday", symbol: "sun.horizon", value: 45)
                preset("Bright", symbol: "sun.max", value: 80)
            }
            .disabled(!available)
            DeviceMessage(text: store.tvMessage, error: store.tvError)
        }
        .padding(22).frame(width: 330)
    }

    private func set(_ value: Int) { Task { await store.setBrightness(value) } }

    private func adjustment(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .regular)).frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }

    private func preset(_ title: String, symbol: String, value: Int) -> some View {
        let active = store.brightness == value
        return Button { set(value) } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                Text(title).font(.system(size: 11, weight: .medium))
                Text("\(value)%").font(.system(size: 10)).opacity(0.6)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(active ? .white : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(active ? GlowTheme.background : GlowTheme.ink)
        }
        .buttonStyle(.plain).accessibilityLabel("\(title), brightness \(value) percent")
    }
}

struct VolumeCard: View {
    @ObservedObject var store: ControlStore

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Sonos volume")
                Spacer()
                if store.sonosConnected {
                    Text(store.muted ? "Muted" : "\(Int(store.volumeDraft))%")
                        .monospacedDigit().accessibilityLabel(store.muted ? "Sonos muted" : "Volume \(Int(store.volumeDraft)) percent")
                } else {
                    Button(store.sonosConnecting ? "Connecting…" : "Connect Sonos") { Task { await store.connectSonos() } }
                        .buttonStyle(.plain).disabled(store.sonosConnecting)
                        .help(store.sonosMessage).accessibilityIdentifier("connectSonosButton")
                }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(GlowTheme.muted)
            HStack(spacing: 12) {
                Button { Task { await store.toggleMute() } } label: {
                    Image(systemName: store.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16)).frame(width: 24, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(store.muted ? "Unmute Sonos" : "Mute Sonos")
                .accessibilityIdentifier("muteButton")
                Slider(value: $store.volumeDraft, in: 0...100) { editing in
                    store.editingVolume = editing
                    if !editing { set(Int(store.volumeDraft)) }
                }
                .accessibilityLabel("Sonos volume").accessibilityValue("\(Int(store.volumeDraft)) percent")
                .accessibilityIdentifier("volumeSlider")
                Button { set(max(0, Int(store.volumeDraft) - 1)) } label: {
                    Image(systemName: "minus").font(.system(size: 13, weight: .semibold)).frame(width: 24, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Lower volume by 1")
                Button { set(min(100, Int(store.volumeDraft) + 1)) } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).frame(width: 24, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Increase volume by 1")
            }
            .disabled(!store.sonosConnected || store.applyingVolume).opacity(store.sonosConnected ? 1 : 0.35)
            if store.sonosError && store.sonosConnected {
                DeviceMessage(text: store.sonosMessage, error: true).accessibilityIdentifier("sonosMessage")
            }
        }
        .padding(18)
    }

    private func set(_ value: Int) { Task { await store.setVolume(value) } }
}
