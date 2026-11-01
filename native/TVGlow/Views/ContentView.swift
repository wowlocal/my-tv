import SwiftUI

/// Mirrors the iOS 27 Remote app: mute · device · power on top, a full-height touch surface,
/// and Play/Pause · Back · TV below. Volume and brightness sit between the surface and the
/// buttons, behind a handle, so each area answers to exactly one kind of touch.
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
            AppleRemoteCard(remote: remote, showDevices: { showingDevices = true }) { statusText }
                .frame(maxHeight: .infinity)
            levels
            bottomButtons.padding(.top, 12)
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
        GlassGroup(spacing: 14) { HStack(spacing: 14) {
            CircleButton(symbol: store.muted ? "speaker.slash.fill" : "speaker.slash", diameter: 50, highlighted: store.muted) {
                feedback += 1
                Task { await store.toggleMute() }
            }
            .disabled(!store.sonosConnected || store.applyingVolume)
            .opacity(store.sonosConnected ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.3), value: store.sonosConnected)
            .accessibilityLabel(store.muted ? "Unmute Sonos" : "Mute Sonos").accessibilityIdentifier("muteButton")

            Button { showingDevices = true } label: {
                HStack(spacing: 8) {
                    TVBadge()
                    Text(deviceName).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        .contentTransition(.opacity)
                    if remote.snapshot.phase.isBusy {
                        ProgressView().controlSize(.small).tint(GlowTheme.muted)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(GlowTheme.muted)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                .opacity(remote.connected ? 1 : 0.55)
                .animation(.snappy(duration: 0.3), value: remote.snapshot.phase)
                .animation(.easeInOut(duration: 0.3), value: deviceName)
                .padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 50)
                .remoteGlass(Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose Apple TV, \(deviceName)").accessibilityIdentifier("appleTVDeviceSelector")
            .popover(isPresented: $showingDevices) {
                AppleTVConnectionView(remote: remote).frame(width: 310).padding(22)
                    .presentationCompactAdaptation(.popover)
            }

            CircleButton(symbol: "power", diameter: 50, pulsing: store.tvPowerBusy, action: togglePower)
                .disabled(store.tvPowerBusy)
                .contextMenu {
                    Button("Turn On TV", systemImage: "power") { powerOn() }
                    Button("Turn Off TV", systemImage: "power.circle") { powerOff() }.disabled(!store.tvConnected)
                }
                .accessibilityLabel(store.tvConnected ? "Turn off TV" : "Turn on TV").accessibilityIdentifier("tvPowerMenuButton")
        } }
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

    /// Display-only: the touch surface keeps every touch for Apple TV.
    private var statusText: some View {
        VStack {
            if let status {
                Text(status).font(.system(size: 12)).foregroundStyle(GlowTheme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).transition(.opacity)
                    .accessibilityIdentifier("statusMessage")
            }
        }
        .animation(.easeOut(duration: 0.2), value: status)
    }

    // MARK: Volume and brightness

    /// Lives below the touch surface, never on it: a swipe that starts on the surface can't
    /// move a level, and a slip off a level bar can't reach Apple TV.
    private var levels: some View {
        VStack(spacing: 6) {
            handle
            if showLevels {
                LevelsPanel(store: store)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(.top, 4)
        .animation(RemoteChrome.reveal, value: showLevels)
    }

    private func setLevels(_ visible: Bool) {
        guard visible != showLevels else { return }
        feedback += 1
        withAnimation(RemoteChrome.reveal) { showLevels = visible }
    }

    /// The only way to show or hide the level bars: tap it, or swipe up / down on it.
    private var handle: some View {
        Capsule().fill(.white.opacity(0.24)).frame(width: 36, height: 5)
            .frame(width: 120, height: 28).contentShape(Rectangle())
            .onTapGesture { setLevels(!showLevels) }
            .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                let dy = value.translation.height
                guard abs(dy) > abs(value.translation.width) else { return }
                if dy < -14 { setLevels(true) } else if dy > 14 { setLevels(false) }
            })
            .accessibilityElement().accessibilityAddTraits(.isButton)
            .accessibilityLabel(showLevels ? "Hide volume and brightness" : "Show volume and brightness")
            .accessibilityIdentifier("levelsToggle")
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if showLevels {
                    SurfaceIcon(symbol: "gearshape", label: "Connections") { showingConnections = true }
                        .accessibilityIdentifier("connectionsButton").transition(.opacity)
                }
            }
    }

    // MARK: Bottom buttons

    private var bottomButtons: some View {
        GlassGroup(spacing: 22) {
            HStack(spacing: 22) {
                remoteButton("Play / pause", symbol: "playpause", command: .playPause, diameter: 77, glyph: 24)
                remoteButton("Back", symbol: "chevron.left", command: .back, diameter: 100, glyph: 36)
                remoteButton("Home", symbol: "tv", command: .home, diameter: 77, glyph: 24)
            }
        }
        .disabled(!remote.connected).opacity(remote.connected ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.3), value: remote.connected)
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
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: store.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .contentTransition(.symbolEffect(.replace)).animation(.snappy, value: store.muted)
                    .frame(width: 22).foregroundStyle(GlowTheme.muted)
                if store.sonosConnected {
                    bar($store.volumeDraft) { editing in
                        store.editingVolume = editing
                        if !editing { Task { await store.setVolume(Int(store.volumeDraft)) } }
                    }
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
                    bar($store.brightnessDraft) { editing in
                        store.editingBrightness = editing
                        if !editing { Task { await store.setBrightness(Int(store.brightnessDraft)) } }
                    }
                    .disabled(store.tvPowerBusy)
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
        .padding(.horizontal, 16).padding(.vertical, 10)
        .remoteGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: store.sonosConnected)
        .animation(.easeInOut(duration: 0.25), value: store.tvConnected)
    }

    /// Levels stay usable while a change is being applied: the store queues the latest one.
    @ViewBuilder
    private func bar(_ level: Binding<Double>, onEditingChanged: @escaping (Bool) -> Void) -> some View {
        #if os(iOS)
        LevelBar(value: level, onEditingChanged: onEditingChanged)
        #else
        Slider(value: level, in: 0...100, onEditingChanged: onEditingChanged)
        #endif
    }

    private func value(_ number: Int) -> some View {
        Text("\(number)").font(.system(size: 13, weight: .medium)).monospacedDigit()
            .contentTransition(.numericText(value: Double(number)))
            .animation(.snappy(duration: 0.25), value: number)
            .foregroundStyle(GlowTheme.muted).frame(width: 28, alignment: .trailing)
    }

    private func offline(_ text: String) -> some View {
        HStack { Text(text).font(.system(size: 13)).foregroundStyle(GlowTheme.muted); Spacer(minLength: 0) }
    }

    private func preset(_ title: String, value: Int) -> some View {
        Button("\(title) · \(value)%") { Task { await store.setBrightness(value) } }
    }
}

#if os(iOS)
/// A level bar driven by one gesture. The level follows the finger from where it was instead of
/// jumping to the touch, and taps or vertical swipes are ignored (see `LevelDrag`), so brushing
/// it never changes the volume or brightness. It thickens while it is being adjusted.
struct LevelBar: View {
    @Binding var value: Double
    var step = 5.0
    let onEditingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var drag = LevelDrag()
    @State private var width = 0.0
    @GestureState private var touching = false

    var body: some View {
        let adjusting = drag.state == .adjusting
        Capsule().fill(.white.opacity(0.14))
            .overlay(alignment: .leading) {
                Rectangle().fill(.white.opacity(isEnabled ? 0.92 : 0.35))
                    .frame(width: width * min(max(value / 100, 0), 1))
            }
            .clipShape(Capsule())
            .frame(height: adjusting ? 12 : 6)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
            .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { gesture in
                    guard isEnabled else { return }
                    let wasAdjusting = drag.state == .adjusting
                    guard let level = drag.move(dx: gesture.translation.width, dy: gesture.translation.height,
                                                width: width, current: value) else { return }
                    if !wasAdjusting { onEditingChanged(true) }
                    value = level
                }
                .onEnded { _ in finish() })
            // Also ends a touch the system cancelled, so a level is never left half-edited.
            .onChange(of: touching) { _, now in if !now { finish() } }
            .animation(.snappy(duration: 0.2), value: adjusting)
            .accessibilityElement()
            .accessibilityAdjustableAction { direction in
                let delta: Double
                switch direction {
                case .increment: delta = step
                case .decrement: delta = -step
                @unknown default: return
                }
                onEditingChanged(true)
                value = min(max(value + delta, 0), 100)
                onEditingChanged(false)
            }
    }

    private func finish() {
        if drag.end() { onEditingChanged(false) }
    }
}
#endif
