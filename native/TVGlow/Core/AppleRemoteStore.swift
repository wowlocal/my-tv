import Foundation
import Combine

enum AppleRemotePhase: Equatable {
    case disconnected, connecting, pairing, connected
    case failed(String)

    var isBusy: Bool { self == .connecting || self == .pairing }
}

struct AppleRemoteDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let model: String?
}

struct AppleRemoteSnapshot: Equatable {
    var devices: [AppleRemoteDevice] = []
    var phase: AppleRemotePhase = .disconnected
    var connectedName: String?
    var canSubmitPIN = false
    var keyboardFocused = false
}

enum AppleRemoteCommand: String, CaseIterable {
    case up, down, left, right, select, back, home, playPause, wake
}

/// Converts cumulative touch-surface translation into discrete remote presses.
/// A drag can repeat navigation, but must never select an item on release.
struct RemoteTouchNavigation {
    private var anchorX = 0.0
    private var anchorY = 0.0
    private var travelled = false

    mutating func move(x: Double, y: Double) -> AppleRemoteCommand? {
        if max(abs(x), abs(y)) >= 12 { travelled = true }
        let dx = x - anchorX, dy = y - anchorY
        guard max(abs(dx), abs(dy)) >= 32 else { return nil }
        anchorX = x; anchorY = y
        return abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
    }

    mutating func end(x: Double, y: Double) -> AppleRemoteCommand? {
        defer { reset() }
        return !travelled && max(abs(x), abs(y)) < 12 ? .select : nil
    }

    mutating func reset() {
        anchorX = 0; anchorY = 0; travelled = false
    }
}

/// Tells a pull-up from the touch surface's bottom edge (reveals the sliders) apart from
/// ordinary navigation that happens to start there.
struct BottomEdgePull {
    static let zone = 48.0
    private(set) var active = false

    /// Call once when a touch begins.
    mutating func begin(startY: Double, surfaceHeight: Double) {
        active = surfaceHeight > 0 && startY > surfaceHeight - Self.zone
    }

    /// Returns true while the touch still counts as a pull. Sideways or downward
    /// movement hands the touch back to navigation for good.
    mutating func move(dx: Double, dy: Double) -> Bool {
        guard active else { return false }
        if (abs(dx) > 20 && abs(dx) > -dy) || dy > 20 { active = false }
        return active
    }

    /// Returns true if the touch ended as an upward pull.
    mutating func end(dx: Double, dy: Double) -> Bool {
        defer { active = false }
        return active && -dy > 24 && -dy > abs(dx)
    }
}

@MainActor
protocol AppleRemoteDriving: AnyObject {
    var snapshot: AppleRemoteSnapshot { get }
    func startDiscovery()
    func stopDiscovery()
    func connect(deviceID: String)
    func disconnect()
    func submitPIN(_ pin: String)
    func press(_ command: AppleRemoteCommand)
    func sendText(_ text: String)
    /// Whether this app already holds pairing credentials for the device.
    /// Only paired devices are connected automatically; pairing always needs the user.
    func isPaired(deviceID: String) -> Bool
}

@MainActor
final class AppleRemoteStore: ObservableObject {
    @Published private(set) var snapshot = AppleRemoteSnapshot()
    @Published var selectedDeviceID: String?
    @Published var pin = ""
    @Published var text = ""
    @Published private(set) var pinSubmitted = false
    @Published private(set) var notice: String?
    @Published private(set) var hasError = false
    private let driver: AppleRemoteDriving
    private let defaults: UserDefaults
    private var observation: Task<Void, Never>?
    private var phaseStarted = Date()
    private var started = false
    /// Cleared by an explicit Disconnect so the app does not fight the user.
    private var autoConnect = true
    /// The device of a connection the app started on its own, if one is in flight.
    private var automaticDeviceID: String?
    private var nextAutomaticCheck = Date.distantPast
    private var automaticFailures = 0
    private var pairedCache: [String: Bool] = [:]

    init(driver: AppleRemoteDriving? = nil, defaults: UserDefaults = .standard) {
        self.driver = driver ?? NativeAppleRemoteDriver()
        self.defaults = defaults
    }

    var connected: Bool { snapshot.phase == .connected }
    var canPair: Bool { selectedDeviceID != nil && !snapshot.phase.isBusy && !connected }
    var canSubmitPIN: Bool { snapshot.canSubmitPIN && !pinSubmitted && Self.validPIN(pin) != nil }

    var message: String {
        if let notice { return notice }
        switch snapshot.phase {
        case .disconnected:
            return snapshot.devices.isEmpty ? "Looking for Apple TVs on your home network…" : "Choose your Apple TV and connect."
        case .connecting: return "Connecting securely to Apple TV…"
        case .pairing: return snapshot.canSubmitPIN ? "Enter the four-digit code shown on your TV." : "Waiting for the pairing code on your TV…"
        case .connected: return "Ready. Use the pad or remote buttons."
        case .failed(let error): return error
        }
    }

    func start() {
        guard !started else { return }
        started = true
        driver.startDiscovery()
        synchronize()
        observation = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
                self?.synchronize()
            }
        }
    }

    func synchronize(now: Date = Date()) {
        var next = driver.snapshot
        if next.phase != snapshot.phase {
            phaseStarted = now
            pinSubmitted = false
            notice = nil
            hasError = false
            if next.phase == .connected {
                pin = ""
                if let selectedDeviceID {
                    defaults.set(selectedDeviceID, forKey: "appleTVDeviceID")
                    pairedCache[selectedDeviceID] = true
                }
                automaticDeviceID = nil
                automaticFailures = 0
            }
        }
        if let id = automaticDeviceID {
            if next.phase == .pairing {
                // An automatic connection must never put a pairing code on the TV.
                driver.disconnect()
                next = driver.snapshot
                pairedCache[id] = false
                automaticDeviceID = nil
            } else if case .failed = next.phase {
                pairedCache[id] = nil
                automaticDeviceID = nil
                automaticFailures += 1
            }
        }
        let limit: TimeInterval = next.phase == .pairing ? 120 : 25
        if next.phase.isBusy && now.timeIntervalSince(phaseStarted) > limit {
            driver.disconnect()
            next = driver.snapshot
            if automaticDeviceID != nil {
                automaticDeviceID = nil
                automaticFailures += 1
            } else {
                notice = "Apple TV did not finish connecting. Check its screen and try again."
                hasError = true
            }
            pinSubmitted = false
        }
        if snapshot.keyboardFocused && !next.keyboardFocused { text = "" }
        if next != snapshot { snapshot = next }
        if !snapshot.devices.contains(where: { $0.id == selectedDeviceID }) && !snapshot.phase.isBusy && !connected {
            let preferred = defaults.string(forKey: "appleTVDeviceID")
            selectedDeviceID = snapshot.devices.first(where: { $0.id == preferred })?.id ?? snapshot.devices.first?.id
        }
        connectAutomaticallyIfPossible(now: now)
    }

    /// Reconnects to an Apple TV this app has already paired with. Connecting only verifies the
    /// stored pairing; it sends no remote commands.
    private func connectAutomaticallyIfPossible(now: Date) {
        guard started, autoConnect, now >= nextAutomaticCheck else { return }
        switch snapshot.phase {
        case .disconnected, .failed: break
        default: return
        }
        nextAutomaticCheck = now.addingTimeInterval(2)
        guard let device = pairedDeviceID() else { return }
        nextAutomaticCheck = now.addingTimeInterval(min(60, 5 * pow(2, Double(min(automaticFailures, 4)))))
        beginAutomaticConnection(to: device, now: now)
    }

    private func beginAutomaticConnection(to device: String, now: Date) {
        selectedDeviceID = device
        automaticDeviceID = device
        notice = nil; hasError = false
        driver.connect(deviceID: device)
        phaseStarted = now
        let next = driver.snapshot
        if next != snapshot { snapshot = next }
    }

    private func pairedDeviceID() -> String? {
        let preferred = defaults.string(forKey: "appleTVDeviceID")
        let ids = snapshot.devices.map(\.id)
        return (ids.filter { $0 == preferred } + ids.filter { $0 != preferred }).first { id in
            if let cached = pairedCache[id] { return cached }
            let paired = driver.isPaired(deviceID: id)
            pairedCache[id] = paired
            return paired
        }
    }

    /// Wakes the TV through Apple TV (HDMI-CEC), first connecting to an already paired Apple TV
    /// when needed. Returns false without starting pairing if no paired Apple TV is available.
    @discardableResult
    func wake(timeout: TimeInterval = 8) async -> Bool {
        if !connected {
            if !snapshot.phase.isBusy {
                guard let device = pairedDeviceID() else { return false }
                autoConnect = true
                beginAutomaticConnection(to: device, now: Date())
            }
            let deadline = Date().addingTimeInterval(timeout)
            while !connected && Date() < deadline {
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return false }
                synchronize()
                switch snapshot.phase {
                case .disconnected, .failed: return false
                default: break
                }
            }
        }
        guard connected else { return false }
        driver.press(.wake)
        return true
    }

    /// Called when the app returns to the foreground. Suspended apps can lose Bonjour browsing
    /// and sockets, so look again and retry the paired Apple TV straight away.
    func resume() {
        guard started else { return }
        automaticFailures = 0
        nextAutomaticCheck = .distantPast
        pairedCache.removeAll()
        #if os(iOS)
        if !connected && !snapshot.phase.isBusy { rescan() }
        #endif
        synchronize()
    }

    func connect() {
        guard canPair, let selectedDeviceID else { return }
        autoConnect = true; automaticDeviceID = nil
        notice = nil; hasError = false; pin = ""; text = ""
        driver.connect(deviceID: selectedDeviceID)
        phaseStarted = Date()
        synchronize()
    }

    func disconnect() {
        autoConnect = false; automaticDeviceID = nil
        driver.disconnect()
        pin = ""; text = ""; pinSubmitted = false; notice = nil; hasError = false
        synchronize()
    }

    func rescan() {
        driver.stopDiscovery()
        driver.startDiscovery()
        synchronize()
    }

    static func validPIN(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count == 4 && value.utf8.allSatisfy { (48...57).contains($0) } ? value : nil
    }

    func submitPIN() {
        guard snapshot.canSubmitPIN, !pinSubmitted, let value = Self.validPIN(pin) else {
            notice = "Enter the four-digit code shown on your Apple TV."
            hasError = true
            return
        }
        pinSubmitted = true
        notice = "Verifying the pairing code…"; hasError = false
        driver.submitPIN(value)
    }

    func press(_ command: AppleRemoteCommand) {
        guard connected else { return }
        driver.press(command)
        notice = nil; hasError = false
    }

    func sendText() {
        guard connected, snapshot.keyboardFocused, !text.isEmpty else { return }
        driver.sendText(text)
        text = ""
        notice = "Text sent to Apple TV."; hasError = false
    }

    func stop() {
        observation?.cancel(); observation = nil; started = false
        driver.stopDiscovery()
        disconnect()
    }
}
