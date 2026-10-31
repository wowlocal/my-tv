import SwiftUI

/// Mirrors the iOS 27 Remote app: mute · device · power on top, a full-height touch surface,
/// and Play/Pause · Back · TV below. Level sliders stay hidden until asked for.
struct ContentView: View {
    @ObservedObject var store: ControlStore
    @ObservedObject var remote: AppleRemoteStore
    @State private var showingConnections = false
    @State private var showingDevices = false
    @State private var showingKeyboard = false
    @State private var flash: String?
    @State private var flashTask: Task<Void, Never>?
    @State private var feedback = 0
    @AppStorage("showLevelSliders") private var showLevels = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            topBar.padding(.bottom, 22)
            AppleRemoteCard(remote: remote, showDevices: { showingDevices = true }) { surfaceAccessory }
                .frame(maxHeight: .infinity)
            bottomButtons.padding(.top, 16)
        }
        .padding(.horizontal, 15).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.black.ignoresSafeArea() }
        .foregroundStyle(GlowTheme.ink).tint(GlowTheme.accent).preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: feedback)
        .sheet(isPresented: $showingConnections) { ConnectionView(store: store) }
        .sheet(isPresented: $showingKeyboard) {
            AppleTVKeyboardView(remote: remote).padding(22).presentationDetents([.height(190)])
        }
        .task { store.start(); remote.start() }
        .onChange(of: scenePhase) { _, phase in
            // Back in the foreground: re-check devices and reconnect without any taps.
            if phase == .active { store.resume(); remote.resume() }
        }
        .onChange(of: remote.snapshot.keyboardFocused) { _, focused in
            // Like the system remote, offer the keyboard as soon as Apple TV asks for text.
            showingKeyboard = focused && remote.connected
        }
        .onChange(of: remote.connected) { _, connected in
            if connected { showingDevices = false } else { showingKeyboard = false }
        }
    }

    // MARK: Top bar

    private var deviceName: String {
        remote.snapshot.connectedName ?? remote.snapshot.devices.first(where: { $0.id == remote.selectedDeviceID })?.name ?? "Apple TV"
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            CircleButton(symbol: store.muted ? "speaker.slash.fill" : "speaker.slash", diameter: 50, highlighted: store.muted) {
                feedback += 1
                Task { await store.toggleMute() }
            }
            .disabled(!store.sonosConnected || store.applyingVolume)
            .opacity(store.sonosConnected ? 1 : 0.4)
            .accessibilityLabel(store.muted ? "Unmute Sonos" : "Mute Sonos").accessibilityIdentifier("muteButton")

            Button { showingDevices = true } label: {
                HStack(spacing: 8) {
                    TVBadge()
                    Text(deviceName).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(GlowTheme.muted)
                }
                .opacity(remote.connected ? 1 : 0.55)
                .padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 50)
                .background(RemoteChrome.fill, in: Capsule())
                .overlay(Capsule().strokeBorder(RemoteChrome.stroke, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose Apple TV, \(deviceName)").accessibilityIdentifier("appleTVDeviceSelector")
            .popover(isPresented: $showingDevices) {
                AppleTVConnectionView(remote: remote).frame(width: 310).padding(22)
                    .presentationCompactAdaptation(.popover)
            }

            CircleButton(symbol: "power", diameter: 50, action: togglePower)
                .disabled(store.tvPowerBusy)
                .contextMenu {
                    Button("Turn On TV", systemImage: "power") { powerOn() }
                    Button("Turn Off TV", systemImage: "power.circle") { powerOff() }.disabled(!store.tvConnected)
                }
                .accessibilityLabel(store.tvConnected ? "Turn off TV" : "Turn on TV").accessibilityIdentifier("tvPowerMenuButton")
        }
    }

    // MARK: Power

    private func togglePower() {
        feedback += 1
        store.tvConnected ? powerOff() : powerOn()
    }

    private func powerOn() {
        // A paired Apple TV is connected on demand, so HDMI-CEC wake needs no extra tap.
        Task {
            await store.turnOnTV(appleWake: { Task { await remote.wake() } })
            show(store.tvMessage)
        }
    }

    private func powerOff() {
        Task {
            await store.turnOffTV()
            show(store.tvMessage)
        }
    }

    private func show(_ message: String) {
        flash = message
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { flash = nil }
        }
    }

    // MARK: Inside the touch surface

    private var status: String? {
        if store.tvPowerBusy { return store.tvMessage }
        if let flash { return flash }
        if remote.hasError { return remote.message }
        return nil
    }

    private var surfaceAccessory: some View {
        VStack(spacing: 10) {
            if let status {
                Text(status).font(.system(size: 12)).foregroundStyle(GlowTheme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).allowsHitTesting(false).transition(.opacity)
                    .accessibilityIdentifier("statusMessage")
            }
            if showLevels {
                LevelsPanel(store: store).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 4) {
                if showLevels {
                    SurfaceIcon(symbol: "gearshape", label: "Connections") { showingConnections = true }
                        .accessibilityIdentifier("connectionsButton")
                }
                SurfaceIcon(symbol: showLevels ? "chevron.down" : "slider.horizontal.3",
                            label: showLevels ? "Hide volume and brightness" : "Show volume and brightness") {
                    withAnimation(.snappy(duration: 0.25)) { showLevels.toggle() }
                }
                .accessibilityIdentifier("levelsToggle")
            }
        }
        .animation(.easeOut(duration: 0.2), value: status)
    }

    // MARK: Bottom buttons

    private var bottomButtons: some View {
        HStack(spacing: 22) {
            remoteButton("Play / pause", symbol: "playpause", command: .playPause, diameter: 77, glyph: 24)
            remoteButton("Back", symbol: "chevron.left", command: .back, diameter: 100, glyph: 36)
            remoteButton("Home", symbol: "tv", command: .home, diameter: 77, glyph: 24)
        }
        .disabled(!remote.connected).opacity(remote.connected ? 1 : 0.4)
    }

    private func remoteButton(_ title: String, symbol: String, command: AppleRemoteCommand, diameter: CGFloat, glyph: CGFloat) -> some View {
        CircleButton(symbol: symbol, diameter: diameter, glyph: glyph, weight: command == .back ? .light : .regular) {
            feedback += 1
            remote.press(command)
        }
        .accessibilityLabel("Apple TV \(title)").help(title).accessibilityIdentifier("appleTV_\(command.rawValue)")
    }
}

/// Volume and brightness, revealed from inside the touch surface.
struct LevelsPanel: View {
    @ObservedObject var store: ControlStore

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: store.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 22).foregroundStyle(GlowTheme.muted)
                if store.sonosConnected {
                    Slider(value: $store.volumeDraft, in: 0...100) { editing in
                        store.editingVolume = editing
                        if !editing { Task { await store.setVolume(Int(store.volumeDraft)) } }
                    }
                    .disabled(store.applyingVolume)
                    .accessibilityLabel("Sonos volume").accessibilityValue("\(Int(store.volumeDraft)) percent")
                    .accessibilityIdentifier("volumeSlider")
                    value(Int(store.volumeDraft))
                } else {
                    offline(store.sonosConnecting ? "Connecting to Sonos…" : "Sonos offline")
                }
            }
            HStack(spacing: 12) {
                Menu {
                    preset("Night", value: 15)
                    preset("Everyday", value: 45)
                    preset("Bright", value: 80)
                } label: {
                    Image(systemName: "sun.max.fill").frame(width: 22).foregroundStyle(GlowTheme.muted)
                }
                .menuStyle(.button).buttonStyle(.plain).fixedSize()
                .disabled(!store.tvConnected || store.applyingBrightness)
                .accessibilityLabel("Brightness presets").accessibilityIdentifier("brightnessPresetsButton")
                if store.tvConnected {
                    Slider(value: $store.brightnessDraft, in: 0...100) { editing in
                        store.editingBrightness = editing
                        if !editing { Task { await store.setBrightness(Int(store.brightnessDraft)) } }
                    }
                    .disabled(store.applyingBrightness || store.tvPowerBusy)
                    .accessibilityLabel("TV brightness").accessibilityValue("\(Int(store.brightnessDraft)) percent")
                    .accessibilityIdentifier("brightnessSlider")
                    value(Int(store.brightnessDraft))
                } else if store.tvConnecting {
                    offline("Connecting to TV…")
                } else {
                    Button("Connect TV") { Task { await store.connectTV() } }
                        .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(GlowTheme.ink)
                        .disabled(store.tvPowerBusy).accessibilityIdentifier("connectTVButton")
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color(white: 0.075), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func value(_ number: Int) -> some View {
        Text("\(number)").font(.system(size: 13, weight: .medium)).monospacedDigit()
            .foregroundStyle(GlowTheme.muted).frame(width: 28, alignment: .trailing)
    }

    private func offline(_ text: String) -> some View {
        HStack { Text(text).font(.system(size: 13)).foregroundStyle(GlowTheme.muted); Spacer(minLength: 0) }
    }

    private func preset(_ title: String, value: Int) -> some View {
        Button("\(title) · \(value)%") { Task { await store.setBrightness(value) } }
    }
}
