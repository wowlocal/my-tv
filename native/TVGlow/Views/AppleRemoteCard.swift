import SwiftUI

/// The large touch surface of the Remote app. Swipe to move, tap to select.
/// `accessory` is pinned to the bottom edge of the surface (status, level sliders).
struct AppleRemoteCard<Accessory: View>: View {
    @ObservedObject var remote: AppleRemoteStore
    let showDevices: () -> Void
    @ViewBuilder let accessory: () -> Accessory
    @FocusState private var padFocused: Bool
    @State private var navigation = RemoteTouchNavigation()
    @State private var touching = false
    @State private var feedback = 0

    private let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)

    var body: some View {
        ZStack {
            shape.fill(Color(white: touching ? 0.15 : 0.122))
                .overlay { shape.strokeBorder(.white.opacity(padFocused ? 0.16 : 0), lineWidth: 1) }
                .contentShape(shape)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard remote.connected else { return }
                        touching = true
                        padFocused = true
                        if let command = navigation.move(x: value.translation.width, y: value.translation.height) {
                            send(command)
                        }
                    }
                    .onEnded { value in
                        touching = false
                        guard remote.connected else { navigation.reset(); return }
                        if let command = navigation.end(x: value.translation.width, y: value.translation.height) {
                            send(command)
                        }
                    })
                .accessibilityLabel("Apple TV touch surface")
                .accessibilityHint("Swipe to navigate. Tap to select.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { send(.select); padFocused = true }
                .accessibilityIdentifier("appleTV_select")
                .accessibilityHidden(!remote.connected)
                .allowsHitTesting(remote.connected)

            if !remote.connected { disconnectedContent }

            VStack { Spacer(minLength: 0); accessory() }.padding(14)
        }
        .animation(.easeOut(duration: 0.12), value: touching)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: feedback)
        .onChange(of: remote.connected) { _, _ in navigation.reset(); touching = false }
        .focusable(remote.connected).focused($padFocused).focusEffectDisabled()
        .onKeyPress(.upArrow) { key(.up) }
        .onKeyPress(.downArrow) { key(.down) }
        .onKeyPress(.leftArrow) { key(.left) }
        .onKeyPress(.rightArrow) { key(.right) }
        .onKeyPress(.return) { key(.select) }
        .onKeyPress(.space) { key(.playPause) }
        .onKeyPress(.escape) { key(.back) }
    }

    private func send(_ command: AppleRemoteCommand) {
        remote.press(command)
        feedback += 1
    }

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

    private func key(_ command: AppleRemoteCommand) -> KeyPress.Result {
        guard remote.connected else { return .ignored }
        remote.press(command)
        return .handled
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
