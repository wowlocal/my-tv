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
    @Environment(\.scenePhase) private var scenePhase
    /// Sonos level shown briefly after an iPhone volume button press.
    @State private var volumeHUD: Int?
    @State private var volumeHUDTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            topBar.padding(.bottom, 32)
            AppleRemoteCard(remote: remote, showDevices: { showingDevices = true }) { statusText } controls: { playbackBar }
                .frame(maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if let volumeHUD {
                        VolumeHUD(level: volumeHUD, muted: store.muted).padding(.top, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    }
                }
            // Its own view, so dragging it re-renders only the drawer: the rest of the remote
            // just moves with the layout.
            LevelsSection(store: store) { showingConnections = true }
            bottomButtons.padding(.top, 11)
        }
        .animation(.easeInOut(duration: 0.3), value: showsPlayback)
        .padding(.horizontal, 16).padding(.bottom, 15)
        .frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.black.ignoresSafeArea() }
        #if os(iOS)
        // The iPhone's volume buttons adjust the Sonos while the remote is in front.
        .background {
            HardwareVolumeButtons(isEnabled: scenePhase == .active && store.sonosConnected) { direction in
                volumeButtonPressed(direction)
            }
            .frame(width: 1, height: 1).accessibilityHidden(true)
        }
        #endif
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
        .onReceive(NotificationCenter.default.publisher(for: .showRemote)) { _ in
            // Opened from Control Center: show the touch surface, not settings left open earlier.
            // Pairing (the device popover) and Apple TV's keyboard stay where they are.
            showingConnections = false
        }
    }

    // MARK: Hardware volume buttons

    private static let volumeButtonStep = 2

    private func volumeButtonPressed(_ direction: Int) {
        guard let level = store.stepVolume(by: direction * Self.volumeButtonStep) else { return }
        withAnimation(.snappy(duration: 0.2)) { volumeHUD = level }
        volumeHUDTask?.cancel()
        volumeHUDTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { volumeHUD = nil }
        }
    }

    // MARK: Top bar

    private var deviceName: String {
        remote.snapshot.connectedName ?? remote.snapshot.devices.first(where: { $0.id == remote.selectedDeviceID })?.name ?? "Apple TV"
    }

    private var topBar: some View {
        GlassGroup(spacing: 16) { HStack(spacing: 16) {
            CircleButton(symbol: store.muted ? "speaker.slash.fill" : "speaker.slash", diameter: 56, glyph: 18.5, highlighted: store.muted) {
                feedback += 1
                Task { await store.toggleMute() }
            }
            .disabled(!store.sonosConnected || store.applyingVolume)
            .opacity(store.sonosConnected ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.3), value: store.sonosConnected)
            .accessibilityLabel(store.muted ? "Unmute Sonos" : "Mute Sonos").accessibilityIdentifier("muteButton")

            Button { showingDevices = true } label: {
                HStack(spacing: 10) {
                    TVBadge()
                    Text(deviceName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        .contentTransition(.opacity)
                    if remote.snapshot.phase.isBusy {
                        ProgressView().controlSize(.small).tint(GlowTheme.muted)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(GlowTheme.muted)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                .opacity(remote.connected ? 1 : 0.55)
                .animation(.snappy(duration: 0.3), value: remote.snapshot.phase)
                .animation(.easeInOut(duration: 0.3), value: deviceName)
                .padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 56)
                .remoteGlass(Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose Apple TV, \(deviceName)").accessibilityIdentifier("appleTVDeviceSelector")
            .popover(isPresented: $showingDevices) {
                AppleTVConnectionView(remote: remote).frame(width: 310).padding(22)
                    .presentationCompactAdaptation(.popover)
            }

            CircleButton(symbol: "power", diameter: 56, glyph: 18.5, pulsing: store.tvPowerBusy, action: togglePower)
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

    // MARK: Now playing

    private var playback: AppleRemotePlayback { remote.snapshot.playback }
    private var showsPlayback: Bool { remote.connected && playback.hasControls }

    /// Like the Remote app: while a show is loaded, skip back · info · subtitles · skip forward sit
    /// along the bottom of the touch surface. The four keep their places; a control the player
    /// on Apple TV doesn't offer is dimmed.
    @ViewBuilder
    private var playbackBar: some View {
        if showsPlayback {
            HStack(spacing: 0) {
                skipButton(forward: false, seconds: playback.skipBackwardInterval, enabled: playback.canSkipBackward)
                Spacer(minLength: 0)
                PadIconButton(symbol: "info.circle") {
                    feedback += 1
                    remote.showInfo()
                }
                .accessibilityLabel("Show info").help("Show info").accessibilityIdentifier("infoButton")
                Spacer(minLength: 0)
                PadIconButton(symbol: playback.subtitlesOn ? "captions.bubble.fill" : "captions.bubble", pulsing: remote.subtitlesPending) {
                    feedback += 1
                    remote.toggleSubtitles()
                }
                .disabled(!playback.canToggleSubtitles)
                .accessibilityLabel(playback.subtitlesOn ? "Turn subtitles off" : "Turn subtitles on")
                .help("Subtitles").accessibilityIdentifier("subtitlesButton")
                Spacer(minLength: 0)
                skipButton(forward: true, seconds: playback.skipForwardInterval, enabled: playback.canSkipForward)
            }
            .padding(.horizontal, 14)
            .transition(.opacity)
        }
    }

    private func skipButton(forward: Bool, seconds: Double, enabled: Bool) -> some View {
        let title = "Skip \(forward ? "forward" : "back") \(Int(seconds.rounded())) seconds"
        return PadIconButton(symbol: AppleRemotePlayback.skipSymbol(forward: forward, seconds: seconds)) {
            feedback += 1
            remote.skip(forward: forward)
        }
        .disabled(!enabled)
        .accessibilityLabel(title).help(title).accessibilityIdentifier(forward ? "skipForward" : "skipBackward")
    }

    // MARK: Bottom buttons

    private var bottomButtons: some View {
        // Spread edge to edge like the Remote app.
        GlassGroup(spacing: 22) {
            HStack(spacing: 0) {
                remoteButton("Play / pause", symbol: "playpause", command: .playPause, diameter: 84, glyph: 21)
                Spacer(minLength: 12)
                remoteButton("Back", symbol: "chevron.left", command: .back, diameter: 110, glyph: 35)
                Spacer(minLength: 12)
                remoteButton("Home", symbol: "tv", command: .home, diameter: 84, glyph: 21)
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

/// Volume and brightness behind their handle, below the touch surface. Keeps the drag in its own
/// state: a finger moving at 120 Hz re-renders only this drawer, not the whole remote.
struct LevelsSection: View {
    @ObservedObject var store: ControlStore
    let showConnections: () -> Void
    /// Plain state (saved to UserDefaults by hand): @AppStorage updates drop the animation
    /// transaction, so a tap on the handle would jump instead of springing.
    @State private var showLevels = UserDefaults.standard.bool(forKey: LevelsSection.levelsKey)
    private static let levelsKey = "showLevelSliders"
    @State private var dragReveal: Double?
    @State private var levelsDrag = RevealDrag()
    @State private var panelHeight = 110.0
    @State private var feedback = 0
    @GestureState private var handleTouched = false

    /// 0 hidden … 1 shown. Follows the finger while the handle is dragged. It drives both the
    /// panel and, through layout, the touch surface above it, so the two always move together.
    private var reveal: Double { dragReveal ?? (showLevels ? 1 : 0) }

    /// Lives below the touch surface, never on it: a swipe that starts on the surface can't
    /// move a level, and a slip off a level bar can't reach Apple TV.
    var body: some View {
        LevelsDrawer(reveal: reveal, panelHeight: panelHeight) { progress in
            handle(progress)
        } panel: { stretch in
            LevelsPanel(store: store, stretch: stretch)
        } onMeasure: { height in
            if abs(height - panelHeight) > 0.5 { panelHeight = height }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: feedback)
    }

    private func setLevels(_ visible: Bool) {
        guard visible != showLevels else { return }
        settle(open: visible)
    }

    /// Springs the panel to its resting place. One animation moves the panel and the touch surface.
    private func settle(open: Bool, velocity: Double = 0) {
        if open != showLevels { feedback += 1 }
        withAnimation(RemoteChrome.reveal(velocity: velocity)) {
            dragReveal = nil
            showLevels = open
        }
        UserDefaults.standard.set(open, forKey: Self.levelsKey)
    }

    /// The only way to show or hide the level bars: tap it, or drag it up / down. The panel
    /// follows the finger and settles where the drag was heading.
    private func handle(_ progress: Double) -> some View {
        GrabberChevron(bend: 1 - 2 * progress)
            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(width: 24, height: 6)
            .animation(.snappy(duration: 0.18)) {
                $0.opacity(handleTouched ? 0.9 : 0.5).scaleEffect(handleTouched ? 1.1 : 1)
            }
            .frame(maxWidth: .infinity).frame(height: 30)
            .contentShape(Rectangle())
            .onTapGesture { setLevels(!showLevels) }
            .gesture(handleDrag)
            .onChange(of: handleTouched) { _, touched in
                guard !touched else { return }
                // The system cancelled the drag (onEnded never ran): settle where it started.
                DispatchQueue.main.async {
                    guard levelsDrag.isDragging else { return }
                    settle(open: levelsDrag.end(at: reveal, predictedDY: 0, velocityDY: 0, height: panelHeight).open)
                }
            }
            .accessibilityElement().accessibilityAddTraits(.isButton)
            .accessibilityLabel(showLevels ? "Hide volume and brightness" : "Show volume and brightness")
            .accessibilityAction { setLevels(!showLevels) }
            .accessibilityIdentifier("levelsToggle")
            .overlay(alignment: .trailing) {
                SurfaceIcon(symbol: "gearshape", label: "Connections", action: showConnections)
                    .accessibilityIdentifier("connectionsButton")
                    .opacity(progress).allowsHitTesting(progress > 0.99).accessibilityHidden(progress < 0.99)
            }
    }

    private var handleDrag: some Gesture {
        // Global coordinates: the handle itself moves with the finger.
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($handleTouched) { _, touched, _ in touched = true }
            .onChanged { value in
                let progress = levelsDrag.progress(from: reveal, dy: value.translation.height, height: panelHeight)
                var exact = Transaction()
                exact.disablesAnimations = true
                withTransaction(exact) { dragReveal = progress }
            }
            .onEnded { value in
                let result = levelsDrag.end(at: reveal, predictedDY: value.predictedEndTranslation.height,
                                            velocityDY: value.velocity.height, height: panelHeight)
                settle(open: result.open, velocity: result.velocity)
            }
    }

}

/// The handle and the level panel below the touch surface, laid out for a reveal value that
/// can overshoot 0…1 (see `RevealGeometry`). Animatable, so a bouncing spring is laid out frame
/// by frame: the touch surface above resizes in step and the panel never gets a negative height.
struct LevelsDrawer<Handle: View, Panel: View>: View, Animatable {
    var reveal: Double
    let panelHeight: Double
    @ViewBuilder let handle: (Double) -> Handle
    @ViewBuilder let panel: (Double) -> Panel
    /// Reports the panel's natural height, without stretch.
    let onMeasure: (Double) -> Void

    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }

    var body: some View {
        let geometry = RevealGeometry(reveal: reveal, height: panelHeight)
        VStack(spacing: 0) {
            handle(geometry.progress).offset(y: geometry.drop)
            panel(geometry.stretch)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: Double.self) { $0.size.height } action: { [stretch = geometry.stretch] height in
                    onMeasure(height - stretch)
                }
                // Slides up with the handle from behind the buttons. No scale: re-rendering the
                // glass at a new size every frame made the drag stutter.
                .opacity(min(1, geometry.progress * 1.5))
                .frame(height: geometry.space + geometry.stretch, alignment: .top)
                .clipShape(BottomEdgeClip())
                .allowsHitTesting(geometry.progress > 0.99)
                .accessibilityHidden(geometry.progress < 0.99)
        }
        .padding(.top, 4)
    }
}

/// Volume and brightness, revealed below the touch surface.
struct LevelsPanel: View {
    @ObservedObject var store: ControlStore
    /// Extra height while overswiped open: the glass stretches, the bars stay put.
    var stretch = 0.0

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
        .padding(.horizontal, 16).padding(.vertical, 10 + stretch / 2)
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
