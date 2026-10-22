import SwiftUI

struct AppleRemoteCard: View {
    @ObservedObject var remote: AppleRemoteStore
    let showDevices: () -> Void
    @FocusState private var padFocused: Bool
    @State private var navigation = RemoteTouchNavigation()
    @State private var touching = false

    var body: some View {
        VStack(spacing: 22) {
            touchSurface
            HStack(spacing: 28) {
                commandButton("Back", symbol: "chevron.backward", command: .back, prominent: true)
                commandButton("Home", symbol: "tv", command: .home)
                commandButton("Play / pause", symbol: "playpause.fill", command: .playPause)
            }
            .disabled(!remote.connected).opacity(remote.connected ? 1 : 0.35)
            if remote.hasError {
                DeviceMessage(text: remote.message, error: true)
                    .multilineTextAlignment(.center).accessibilityIdentifier("appleTVMessage")
            }
        }
        .onChange(of: remote.connected) { _, _ in navigation.reset(); touching = false }
    }

    private var touchSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.135)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(.white.opacity(padFocused ? 0.24 : 0.055), lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.white.opacity(touching ? 0.025 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard remote.connected else { return }
                        touching = true
                        padFocused = true
                        if let command = navigation.move(x: value.translation.width, y: value.translation.height) {
                            remote.press(command)
                        }
                    }
                    .onEnded { value in
                        touching = false
                        guard remote.connected else { navigation.reset(); return }
                        if let command = navigation.end(x: value.translation.width, y: value.translation.height) {
                            remote.press(command)
                        }
                    })
                .accessibilityLabel("Apple TV touch surface")
                .accessibilityHint("Swipe to navigate. Click to select. You can also use the arrow buttons or keyboard.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { remote.press(.select); padFocused = true }
                .accessibilityIdentifier("appleTV_select")
                .accessibilityHidden(!remote.connected)
                .allowsHitTesting(remote.connected)

            if remote.connected {
                VStack {
                    padButton(.up, symbol: "chevron.up", label: "Up")
                    Spacer()
                    HStack {
                        padButton(.left, symbol: "chevron.left", label: "Left")
                        Spacer()
                        VStack(spacing: 7) {
                            Image(systemName: "hand.draw").font(.system(size: 25, weight: .ultraLight))
                            Text("Swipe to navigate").font(.system(size: 11, weight: .medium))
                            Text("Click to select").font(.system(size: 10)).opacity(0.6)
                        }
                        .foregroundStyle(.white.opacity(0.28)).allowsHitTesting(false).accessibilityHidden(true)
                        Spacer()
                        padButton(.right, symbol: "chevron.right", label: "Right")
                    }
                    Spacer()
                    padButton(.down, symbol: "chevron.down", label: "Down")
                }
                .padding(12)
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "appletv.fill").font(.system(size: 34, weight: .light)).foregroundStyle(.white.opacity(0.65))
                    VStack(spacing: 6) {
                        Text(remote.snapshot.phase.isBusy ? "Connecting to Apple TV" : "Your TV. At your fingertips.")
                            .font(.system(size: 16, weight: .medium))
                        Text(remote.snapshot.phase == .pairing ? "Enter the code from your TV to pair." : "Choose an Apple TV to get started.")
                            .font(.system(size: 11)).foregroundStyle(GlowTheme.muted)
                    }
                    Button(action: showDevices) {
                        HStack(spacing: 7) {
                            if remote.snapshot.phase.isBusy { ProgressView().controlSize(.mini) }
                            Text(remote.snapshot.phase == .pairing ? "Enter code" : remote.snapshot.phase.isBusy ? "View connection" : "Connect Apple TV")
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 17).padding(.vertical, 11)
                        .background(.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("appleTVOpenConnectionButton")
                }
                .padding(24).multilineTextAlignment(.center)
            }
        }
        .frame(height: 300)
        .focusable(remote.connected).focused($padFocused).focusEffectDisabled()
        .onKeyPress(.upArrow) { key(.up) }
        .onKeyPress(.downArrow) { key(.down) }
        .onKeyPress(.leftArrow) { key(.left) }
        .onKeyPress(.rightArrow) { key(.right) }
        .onKeyPress(.return) { key(.select) }
        .onKeyPress(.space) { key(.playPause) }
        .onKeyPress(.escape) { key(.back) }
        .help("Swipe or click to navigate. Arrow keys move, Return selects, Space plays or pauses, Escape goes back.")
    }

    private func key(_ command: AppleRemoteCommand) -> KeyPress.Result {
        guard remote.connected else { return .ignored }
        remote.press(command)
        return .handled
    }

    private func padButton(_ command: AppleRemoteCommand, symbol: String, label: String) -> some View {
        Button { remote.press(command); padFocused = true } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.32)).frame(width: 36, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Apple TV \(label)").accessibilityIdentifier("appleTV_\(command.rawValue)")
    }

    private func commandButton(_ title: String, symbol: String, command: AppleRemoteCommand, prominent: Bool = false) -> some View {
        Button { remote.press(command) } label: {
            Image(systemName: symbol).font(.system(size: command == .back ? 27 : 23, weight: .medium))
                .frame(width: 72, height: 72).contentShape(Circle())
        }
        .buttonStyle(RemoteButtonStyle(prominent: prominent))
        .accessibilityLabel("Apple TV \(title)").help(title).accessibilityIdentifier("appleTV_\(command.rawValue)")
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
