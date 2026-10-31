import Foundation
import Combine

@MainActor
final class ControlStore: ObservableObject {
    @Published var tvAddress: String
    @Published var sonosAddress: String
    @Published var tvMAC: String
    @Published var wakeWithAppleTV: Bool { didSet { defaults.set(wakeWithAppleTV, forKey: "wakeWithAppleTV") } }
    @Published private(set) var tvPowerBusy = false
    @Published private(set) var tvConnected = false
    @Published private(set) var tvConnecting = false
    @Published private(set) var awaitingTVApproval = false
    @Published private(set) var brightness: Int?
    @Published var brightnessDraft: Double = 0
    @Published var editingBrightness = false
    @Published private(set) var applyingBrightness = false
    @Published private(set) var tvMessage = "Connect your TV to begin."
    @Published private(set) var tvError = false

    @Published private(set) var sonosConnected = false
    @Published private(set) var sonosConnecting = false
    @Published private(set) var sonosName = "Sonos Arc Ultra"
    @Published private(set) var volume: Int?
    @Published var volumeDraft: Double = 0
    @Published var editingVolume = false
    @Published private(set) var applyingVolume = false
    @Published private(set) var muted = false
    @Published private(set) var sonosMessage = "Connecting to your soundbar…"
    @Published private(set) var sonosError = false

    private let wakeSender: TVWakeSending
    private let tv: TVCommunicating
    private let sonos: SonosCommunicating
    private let vault: PairingStoring
    private let defaults: UserDefaults
    private var tvHost: String?
    private var sonosHost: String?
    private var monitoring: Task<Void, Never>?
    private var started = false
    private var tvAutoFailures = 0
    private var pairedHosts: [String: Bool] = [:]

    init(tv: TVCommunicating? = nil, sonos: SonosCommunicating? = nil,
         vault: PairingStoring = PairingStore(), wakeSender: TVWakeSending? = nil, defaults: UserDefaults = .standard) {
        self.tv = tv ?? WebOSClient()
        self.wakeSender = wakeSender ?? WakeOnLAN()
        self.sonos = sonos ?? SonosClient()
        self.vault = vault
        self.defaults = defaults
        self.tvMAC = defaults.string(forKey: "tvMAC") ?? "74:E6:B8:2D:7F:2C"
        self.wakeWithAppleTV = defaults.object(forKey: "wakeWithAppleTV") as? Bool ?? true
        self.tvAddress = defaults.string(forKey: "tvAddress") ?? "192.168.2.159"
        self.sonosAddress = defaults.string(forKey: "sonosAddress") ?? "192.168.0.206"
    }

    func start() {
        guard !started else { return }
        started = true
        Task {
            await connectSonos()
            await reconnectTVIfPaired()
        }
        monitoring = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                guard let self else { return }
                await self.refresh()
                // Local-network permission can be granted after the first request fails.
                // Retry read-only soundbar discovery while it is offline.
                if !self.sonosConnected { await self.connectSonos() }
                await self.reconnectTVIfPaired()
            }
        }
    }

    /// Called when the app returns to the foreground: sockets may have closed while it was suspended.
    func resume() {
        guard started else { return }
        tvAutoFailures = 0
        pairedHosts.removeAll()
        Task {
            await refresh()
            if !sonosConnected { await connectSonos() }
            await reconnectTVIfPaired()
        }
    }

    private func isPaired(_ host: String) -> Bool {
        if let known = pairedHosts[host] { return known }
        let paired = vault.key(for: host) != nil
        pairedHosts[host] = paired
        return paired
    }

    /// Reconnects to a TV this app has already paired with as soon as it answers on the network.
    /// It only reads settings: it never pairs, wakes or changes the TV.
    func reconnectTVIfPaired() async {
        guard !tvConnected, !tvConnecting, !tvPowerBusy, !applyingBrightness, !editingBrightness, tvAutoFailures < 3,
              let host = try? LocalAddress.validated(tvAddress), isPaired(host) else { return }
        guard await wakeSender.isReachable(host: host) else {
            if !tvError && !tvConnected && !tvPowerBusy { tvMessage = "TV is off. TV Glow connects when it turns on." }
            return
        }
        guard !tvConnected, !tvConnecting, !tvPowerBusy, !applyingBrightness else { return }
        await connectTV()
        tvAutoFailures = tvConnected ? 0 : tvAutoFailures + 1
    }

    func connectTV(whileWaking: Bool = false) async {
        guard (!tvPowerBusy || whileWaking), !tvConnecting, !applyingBrightness else { return }
        tvConnecting = true
        tvConnected = false
        tvError = false
        awaitingTVApproval = false
        brightness = nil
        tvMessage = "Connecting to LG C1…"
        defer { tvConnecting = false; awaitingTVApproval = false }
        do {
            let host = try LocalAddress.validated(tvAddress)
            let key = try await tv.connect(host: host, key: vault.key(for: host)) { [weak self] in
                self?.awaitingTVApproval = true
                self?.tvMessage = "Choose Accept on the TV’s connection request."
            }
            try vault.save(key, for: host)
            pairedHosts[host] = true
            tvHost = host
            defaults.set(host, forKey: "tvAddress")
            let current = try await tv.brightness()
            brightness = current
            brightnessDraft = Double(current)
            tvConnected = true
            tvAutoFailures = 0
            tvMessage = "Live from your TV."
        } catch {
            tv.disconnect()
            tvMessage = error.localizedDescription
            tvError = true
        }
    }

    func turnOffTV() async {
        guard tvConnected, !tvPowerBusy, !tvConnecting, !applyingBrightness, !editingBrightness else { return }
        tvPowerBusy = true; tvError = false
        tvMessage = "Turning off the TV…"
        defer { tvPowerBusy = false }
        do {
            try await tv.powerOff()
            tv.disconnect()
            tvConnected = false
            brightness = nil
            tvMessage = "TV accepted the power-off command."
        } catch {
            tvMessage = "Power off was not confirmed: \(error.localizedDescription)"
            tvError = true
        }
    }

    func turnOnTV(appleWake: (() -> Void)? = nil) async {
        guard !tvPowerBusy, !tvConnecting, !applyingBrightness, !editingBrightness else { return }
        tvPowerBusy = true; tvError = false
        defer { tvPowerBusy = false }
        do {
            let host = try LocalAddress.validated(tvAddress)
            // Validate before sending either kind of wake command.
            _ = try WakeOnLAN.packet(mac: tvMAC)
            // iOS blocks broadcasts without Apple's multicast entitlement, so a failed network
            // wake must not stop the Apple TV (HDMI-CEC) route.
            let appleTVWakes = wakeWithAppleTV && appleWake != nil
            do { try wakeSender.send(host: host, mac: tvMAC) } catch { if !appleTVWakes { throw error } }
            defaults.set(tvMAC, forKey: "tvMAC")
            if appleTVWakes { appleWake?() }
            tvMessage = "Wake sent. Waiting for the TV…"
            guard vault.key(for: host) != nil else {
                tvMessage = "Wake sent. Click Connect TV once it is on to pair."
                return
            }
            // Probe the port before pairing, so an off TV cannot hang registration.
            for _ in 0..<10 {
                if await wakeSender.isReachable(host: host) {
                    await connectTV(whileWaking: true)
                    if tvConnected {
                        tvMessage = "TV is reachable. Brightness is \(brightness ?? 0)%."
                        return
                    }
                    if awaitingTVApproval { return }
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            tvMessage = "Wake sent, but TV did not reconnect. Enable TV On with Mobile on LG, or connect Apple TV for HDMI-CEC wake. Wake-on-LAN may be blocked between network subnets."
            tvError = true
        } catch {
            tvMessage = error.localizedDescription
            tvError = true
        }
    }

    func connectSonos() async {
        guard !sonosConnecting, !applyingVolume else { return }
        sonosConnecting = true
        sonosError = false
        defer { sonosConnecting = false }
        do {
            let host = try LocalAddress.validated(sonosAddress)
            let name = try await sonos.identify(host: host)
            let current = try await sonos.state(host: host)
            sonosHost = host
            defaults.set(host, forKey: "sonosAddress")
            sonosName = name
            updateSonos(current)
            sonosConnected = true
            sonosMessage = "Live from your soundbar."
        } catch {
            sonosConnected = false
            volume = nil
            sonosMessage = error.localizedDescription
            sonosError = true
        }
    }

    func refresh() async {
        if tvConnected && !tvPowerBusy && !tvConnecting && !applyingBrightness && !editingBrightness {
            do {
                let value = try await tv.brightness()
                if tvConnected && !tvPowerBusy && !applyingBrightness && !editingBrightness {
                    brightness = value
                    brightnessDraft = Double(value)
                }
            } catch {
                guard !tvPowerBusy, tvConnected else { return }
                tvConnected = false
                tvMessage = "TV disconnected. TV Glow reconnects when it is back on."
                tvError = false
            }
        }
        if sonosConnected && !sonosConnecting && !applyingVolume && !editingVolume, let host = sonosHost {
            do {
                let state = try await sonos.state(host: host)
                if !applyingVolume && !editingVolume { updateSonos(state) }
            } catch {
                sonosConnected = false
                sonosMessage = "Soundbar disconnected. Check its network and reconnect."
                sonosError = true
            }
        }
    }

    func setBrightness(_ target: Int) async {
        guard tvConnected, !tvPowerBusy, !applyingBrightness, (0...100).contains(target) else { return }
        applyingBrightness = true
        tvError = false
        tvMessage = "Adjusting the glow…"
        defer { applyingBrightness = false }
        do {
            try await tv.setBrightness(target)
            try await Task.sleep(nanoseconds: 300_000_000)
            let actual = try await tv.brightness()
            brightness = actual
            brightnessDraft = Double(actual)
            guard actual == target else {
                throw ControlError.device("The TV kept its previous brightness. Check its Energy Saving setting.")
            }
            tvMessage = "Brightness set to \(actual)%."
        } catch {
            if let brightness { brightnessDraft = Double(brightness) }
            tvMessage = error.localizedDescription
            tvError = true
        }
    }

    func setVolume(_ target: Int) async {
        guard sonosConnected, let host = sonosHost, !applyingVolume, (0...100).contains(target) else { return }
        applyingVolume = true
        sonosError = false
        sonosMessage = "Adjusting volume…"
        defer { applyingVolume = false }
        do {
            try await sonos.setVolume(target, host: host)
            let actual = try await sonos.state(host: host)
            updateSonos(actual)
            guard actual.volume == target else { throw ControlError.device("Sonos kept its previous volume. Check the soundbar’s volume limit.") }
            sonosMessage = "Volume set to \(actual.volume)%."
        } catch {
            if let volume { volumeDraft = Double(volume) }
            sonosMessage = error.localizedDescription
            sonosError = true
        }
    }

    func toggleMute() async {
        guard sonosConnected, let host = sonosHost, !applyingVolume else { return }
        applyingVolume = true
        sonosError = false
        let target = !muted
        defer { applyingVolume = false }
        do {
            try await sonos.setMuted(target, host: host)
            let actual = try await sonos.state(host: host)
            updateSonos(actual)
            guard actual.muted == target else { throw ControlError.device("Sonos did not confirm the mute change.") }
            sonosMessage = actual.muted ? "Soundbar muted." : "Soundbar unmuted."
        } catch {
            sonosMessage = error.localizedDescription
            sonosError = true
        }
    }

    private func updateSonos(_ state: SonosState) {
        volume = state.volume
        volumeDraft = Double(state.volume)
        muted = state.muted
    }

    func forgetTV() {
        guard !tvConnecting, !tvPowerBusy, !applyingBrightness else { return }
        if let host = tvHost ?? (try? LocalAddress.validated(tvAddress)) { vault.remove(for: host); pairedHosts[host] = false }
        tv.disconnect()
        tvConnected = false
        brightness = nil
        tvMessage = "Pairing removed from this device. Connect to pair again."
        tvError = false
    }
}
