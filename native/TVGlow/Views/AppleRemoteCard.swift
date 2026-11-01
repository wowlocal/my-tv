import SwiftUI

/// The large touch surface of the Remote app. Swipe to move, tap to select. Every touch on it
/// belongs to Apple TV: nothing else on the surface reacts to touches.
/// `accessory` is pinned to the bottom edge of the surface and is display-only (status text).
struct AppleRemoteCard<Accessory: View>: View {
    @ObservedObject var remote: AppleRemoteStore
    let showDevices: () -> Void
    @ViewBuilder let accessory: () -> Accessory
    @FocusState private var padFocused: Bool
    @State private var navigation = RemoteTouchNavigation()
    @State private var feedback = 0
    @State private var size: CGSize = .zero
    /// Where the finger is, for the soft glow that follows it.
    @State private var touchPoint: CGPoint?
    @State private var ripples: [Ripple] = []
    @State private var cue: DirectionCue?

    private let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)

    var body: some View {
        ZStack {
            shape.fill(Color(white: 0.122))
            effects.clipShape(shape).allowsHitTesting(false)
            touchLayer
            if !remote.connected {
                disconnectedContent.transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
            VStack { Spacer(minLength: 0); accessory() }.padding(14).allowsHitTesting(false)
        }
        .overlay { shape.strokeBorder(.white.opacity(padFocused ? 0.16 : 0), lineWidth: 1) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .animation(.easeInOut(duration: 0.3), value: remote.connected)
        .animation(.easeInOut(duration: 0.25), value: remote.snapshot.phase)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: feedback)
        .onChange(of: remote.connected) { _, _ in navigation.reset(); touchPoint = nil }
        .focusable(remote.connected).focused($padFocused).focusEffectDisabled()
        .onKeyPress(.upArrow) { key(.up) }
        .onKeyPress(.downArrow) { key(.down) }
        .onKeyPress(.leftArrow) { key(.left) }
        .onKeyPress(.rightArrow) { key(.right) }
        .onKeyPress(.return) { key(.select) }
        .onKeyPress(.space) { key(.playPause) }
        .onKeyPress(.escape) { key(.back) }
    }

    // MARK: Touch handling

    private var touchLayer: some View {
        Color.clear
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard remote.connected else { return }
                    padFocused = true
                    if touchPoint == nil {
                        withAnimation(.easeOut(duration: 0.18)) { touchPoint = value.location }
                    } else {
                        touchPoint = value.location
                    }
                    if let command = navigation.move(x: value.translation.width, y: value.translation.height) {
                        send(command)
                    }
                }
                .onEnded { value in
                    withAnimation(.easeOut(duration: 0.4)) { touchPoint = nil }
                    guard remote.connected else { navigation.reset(); return }
                    if let command = navigation.end(x: value.translation.width, y: value.translation.height) {
                        send(command, at: value.location)
                    }
                })
            .accessibilityLabel("Apple TV touch surface")
            .accessibilityHint("Swipe to navigate. Tap to select.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { send(.select); padFocused = true }
            .accessibilityIdentifier("appleTV_select")
            .accessibilityHidden(!remote.connected)
    }

    private func send(_ command: AppleRemoteCommand, at point: CGPoint? = nil) {
        remote.press(command)
        feedback += 1
        switch command {
        case .select: ripple(at: point ?? CGPoint(x: size.width / 2, y: size.height / 2))
        case .up, .down, .left, .right: flash(command)
        default: break
        }
    }

    private func key(_ command: AppleRemoteCommand) -> KeyPress.Result {
        guard remote.connected else { return .ignored }
        send(command)
        return .handled
    }

    // MARK: Feedback animations

    private var effects: some View {
        ZStack {
            if let touchPoint {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.13), .white.opacity(0.04), .clear],
                                         center: .center, startRadius: 0, endRadius: 110))
                    .frame(width: 220, height: 220)
                    .position(touchPoint)
                    .transition(.opacity)
            }
            ForEach(ripples) { ripple in
                RippleView().position(ripple.point)
            }
            if let cue {
                Image(systemName: cue.symbol).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cue.alignment)
                    .padding(22)
                    .id(cue.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(cue.nudge)),
                                            removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ripple(at point: CGPoint) {
        let ripple = Ripple(point: point)
        ripples.append(ripple)
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            ripples.removeAll { $0.id == ripple.id }
        }
    }

    private func flash(_ command: AppleRemoteCommand) {
        let next = DirectionCue(command: command)
        withAnimation(.easeOut(duration: 0.12)) { cue = next }
        Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            if cue?.id == next.id { withAnimation(.easeIn(duration: 0.3)) { cue = nil } }
        }
    }

    // MARK: Not connected

    @ViewBuilder private var disconnectedContent: some View {
        let phase = remote.snapshot.phase
        if phase.isBusy && phase != .pairing {
            ProgressView().tint(.white.opacity(0.5)).accessibilityLabel("Connecting to Apple TV")
        } else {
            Button(action: showDevices) {
                Text(phase == .pairing ? "Enter the code shown on your TV" : "Connect Apple TV")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    .padding(20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("appleTVOpenConnectionButton")
        }
    }
}

private struct Ripple: Identifiable {
    let id = UUID()
    let point: CGPoint
}

/// A ring that expands and fades where the surface was tapped.
private struct RippleView: View {
    @State private var expanded = false

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(expanded ? 0 : 0.12))
            Circle().strokeBorder(.white.opacity(expanded ? 0 : 0.45), lineWidth: 1.5)
        }
        .frame(width: 130, height: 130)
        .scaleEffect(expanded ? 1.25 : 0.2)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { expanded = true } }
    }
}

/// A chevron that flashes at the edge a swipe moved towards.
private struct DirectionCue: Equatable {
    let id = UUID()
    let command: AppleRemoteCommand

    var symbol: String {
        switch command {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        default: return "chevron.right"
        }
    }

    var alignment: Alignment {
        switch command {
        case .up: return .top
        case .down: return .bottom
        case .left: return .leading
        default: return .trailing
        }
    }

    /// Slides in from slightly further inside, as if pushed towards the edge.
    var nudge: CGSize {
        switch command {
        case .up: return CGSize(width: 0, height: 10)
        case .down: return CGSize(width: 0, height: -10)
        case .left: return CGSize(width: 10, height: 0)
        default: return CGSize(width: -10, height: 0)
        }
    }
}

struct AppleTVConnectionView: View {
    @ObservedObject var remote: AppleRemoteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Apple TV", systemImage: "appletv.fill").font(.system(size: 16, weight: .semibold))
                Spacer()
                ConnectionBadge(connected: remote.connected, busy: remote.snapshot.phase.isBusy)
            }
            if remote.connected {
                Text(remote.snapshot.connectedName ?? "Apple TV").font(.system(size: 14, weight: .medium))
                Button("Disconnect") { remote.disconnect() }.controlSize(.large)
            } else {
                if !remote.snapshot.devices.isEmpty {
                    Picker("Device", selection: $remote.selectedDeviceID) {
                        ForEach(remote.snapshot.devices) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .disabled(remote.snapshot.phase.isBusy).accessibilityIdentifier("appleTVDevicePicker")
                }
                if remote.snapshot.phase == .pairing {
                    SecureField("4-digit TV code", text: $remote.pin)
                        .textFieldStyle(.roundedBorder).font(.system(size: 20, design: .monospaced))
                        .onSubmit { if remote.canSubmitPIN { remote.submitPIN() } }
                        .accessibilityIdentifier("appleTVPINField")
                    Button(remote.pinSubmitted ? "Verifying…" : "Pair Apple TV") { remote.submitPIN() }
                        .disabled(!remote.canSubmitPIN).accessibilityIdentifier("appleTVPairPINButton")
                }
                HStack {
                    if remote.snapshot.phase.isBusy {
                        Button("Cancel connection") { remote.disconnect() }
                    } else if remote.snapshot.devices.isEmpty {
                        Button("Search again") { remote.rescan() }
                    } else {
                        Button("Connect") { remote.connect() }.disabled(!remote.canPair)
                            .accessibilityIdentifier("appleTVConnectButton")
                        Spacer()
                        Button { remote.rescan() } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("Search for Apple TVs")
                    }
                }
                .controlSize(.large)
            }
            DeviceMessage(text: remote.message, error: remote.hasError).accessibilityIdentifier("appleTVMessage")
        }
        .foregroundStyle(GlowTheme.ink).tint(GlowTheme.accent).preferredColorScheme(.dark)
    }
}

struct AppleTVKeyboardView: View {
    @ObservedObject var remote: AppleRemoteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Type on Apple TV", systemImage: "keyboard").font(.system(size: 16, weight: .semibold))
            HStack(spacing: 10) {
                TextField("Search or enter text…", text: $remote.text)
                    .textFieldStyle(.roundedBorder).onSubmit { remote.sendText() }
                    .disabled(!remote.connected || !remote.snapshot.keyboardFocused)
                    .accessibilityIdentifier("appleTVTextField")
                Button { remote.sendText() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 24)) }
                    .buttonStyle(.plain).disabled(!remote.connected || !remote.snapshot.keyboardFocused || remote.text.isEmpty)
                    .accessibilityLabel("Send text to Apple TV").accessibilityIdentifier("appleTVSendTextButton")
            }
            DeviceMessage(text: remote.snapshot.keyboardFocused ? "Text entry is active on Apple TV." : "Open a search or text field on Apple TV first.")
            if remote.notice != nil { DeviceMessage(text: remote.message, error: remote.hasError) }
        }
        .foregroundStyle(GlowTheme.ink).tint(GlowTheme.accent).preferredColorScheme(.dark)
    }
}
