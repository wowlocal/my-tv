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
    var playback = AppleRemotePlayback()
}

enum AppleRemoteCommand: String, CaseIterable {
    case up, down, left, right, select, back, home, playPause, wake, sleep
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

/// Turns a drag on a level bar (volume, brightness) into a new level. The level moves with
/// the finger from where it was, never jumps to where the finger landed, and only once the
/// touch is clearly sideways, so a stray tap or a vertical swipe never changes a level.
struct LevelDrag {
    /// How far a touch moves before it counts as sideways (adjusting) or not (ignored).
    static let slop = 8.0
    enum State: Equatable { case idle, undecided, adjusting, ignored }
    private(set) var state = State.idle
    private var startLevel = 0.0
    private var anchorX = 0.0

    /// Feed every touch movement. `current` is read on the first call of a touch.
    /// Returns the new level while adjusting, otherwise nil.
    mutating func move(dx: Double, dy: Double, width: Double, current: Double,
                       range: ClosedRange<Double> = 0...100) -> Double? {
        if state == .idle { state = .undecided; startLevel = current }
        if state == .undecided, max(abs(dx), abs(dy)) >= Self.slop {
            if width > 0 && abs(dx) > abs(dy) { state = .adjusting; anchorX = dx } else { state = .ignored }
        }
        guard state == .adjusting else { return nil }
        let level = startLevel + (dx - anchorX) / width * (range.upperBound - range.lowerBound)
        return min(max(level, range.lowerBound), range.upperBound)
    }

    /// Ends the touch. Returns true if it changed the level, which should then be applied.
    mutating func end() -> Bool {
        defer { state = .idle }
        return state == .adjusting
    }
}

/// Lets a finger drag a panel open (up) or closed (down) 1:1, then picks where it settles
/// from where the drag was heading, so a short flick is enough and a slow drag can be undone.
/// Values past 0…1 are an overswipe; `RevealGeometry` turns them into rubber-band give, which
/// approaches its limit smoothly, so the drag itself is barely bounded.
struct RevealDrag {
    /// Progress (0 hidden … 1 shown) when the drag began; nil between drags.
    private(set) var start: Double?
    var isDragging: Bool { start != nil }

    /// Progress for the current vertical translation. `current` is read on the first call.
    mutating func progress(from current: Double, dy: Double, height: Double) -> Double {
        let base = start ?? current
        start = base
        guard height > 0 else { return base }
        return min(max(base - dy / height, -4), 5)
    }

    /// Ends the drag. Returns whether the panel settles open, and the finger's speed in progress
    /// per second (positive opens) for `RevealSettle`, so the release carries on exactly as fast
    /// as the finger moved: a hard flick overshoots into the rubber band and springs back.
    mutating func end(at progress: Double, predictedDY: Double, velocityDY: Double, height: Double) -> (open: Bool, velocity: Double) {
        let base = start ?? progress
        start = nil
        guard height > 0 else { return (progress > 0.5, 0) }
        let open = base - predictedDY / height > 0.5
        return (open, min(max(-velocityDY / height, -30), 30))
    }
}

/// Where the level panel is drawn for a reveal value. Within 0…1 the panel follows it exactly.
/// Beyond that it gives like rubber, with growing resistance: past 1 the panel stretches taller,
/// below 0 the handle drops below its resting place.
struct RevealGeometry {
    static let stretchLimit = 44.0
    static let dropLimit = 28.0
    /// How far below its place the panel starts as it appears; it rises as it opens.
    static let rise = 14.0
    /// Height of the soft, dissolving lower edge while the panel appears (none when fully open).
    static let fade = 30.0
    /// 0…1, how much of the panel is shown.
    let progress: Double
    /// Height the panel takes up in the layout, excluding stretch.
    let space: Double
    /// Extra height of the panel past fully open.
    let stretch: Double
    /// How far the handle sits below its resting place past fully closed.
    let drop: Double

    init(reveal: Double, height: Double) {
        progress = min(max(reveal, 0), 1)
        space = max(height, 0) * progress
        stretch = Self.rubber(max(0, reveal - 1) * height, limit: Self.stretchLimit)
        drop = Self.rubber(max(0, -reveal) * height, limit: Self.dropLimit)
    }

    /// Scroll-view-style rubber band: about half the finger's travel at first, never past `limit`.
    static func rubber(_ distance: Double, limit: Double) -> Double {
        guard distance > 0, limit > 0 else { return 0 }
        return (1 - 1 / (distance * 0.55 / limit + 1)) * limit
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
    /// Skips by the player's preferred interval (10 s when it has none).
    func skip(forward: Bool)
    /// Turns subtitles on or off on Apple TV.
    func setSubtitles(_ on: Bool)
    func sendText(_ text: String)
    /// Whether Apple TV is asleep: pyatv's SystemStatus (1 asleep, 2 screensaver, 3 awake, 4 idle),
    /// nil when unknown. Read-only.
    func attentionState() async -> Int?
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
    /// A subtitle change was sent and Apple TV hasn't reported it back yet.
    @Published private(set) var subtitlesPending = false
    private var subtitleRequest: (target: Bool, sent: Date)?
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
        if let request = subtitleRequest {
            // The button shows what Apple TV reports, so wait for its readback before settling.
            if next.playback.subtitlesOn == request.target || !next.playback.active || next.phase != .connected {
                subtitleRequest = nil; subtitlesPending = false
            } else if now.timeIntervalSince(request.sent) > 5 {
                subtitleRequest = nil; subtitlesPending = false
                notice = "The app on Apple TV didn't change subtitles."; hasError = true
            }
        }
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

    static let asleep = 1

    /// Turns the TV on through Apple TV (HDMI-CEC), first connecting to an already paired Apple TV
    /// when needed. Apple TV only tells the TV to switch on when it wakes from sleep, so an Apple TV
    /// that is still awake (the TV was switched off on its own) is put to sleep first, and woken
    /// once it reports being asleep. Returns false without starting pairing if no paired Apple TV
    /// is available.
    @discardableResult
    func wake(timeout: TimeInterval = 8, sleepTimeout: TimeInterval = 6, poll: TimeInterval = 0.5) async -> Bool {
        guard await ensureConnected(timeout: timeout) else { return false }
        if let state = await driver.attentionState(), state != Self.asleep {
            driver.press(.sleep)
            let deadline = Date().addingTimeInterval(sleepTimeout)
            while Date() < deadline {
                do { try await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000)) } catch { return false }
                synchronize()
                if connected, await driver.attentionState() == Self.asleep { break }
            }
            guard await ensureConnected(timeout: timeout) else { return false }
        }
        driver.press(.wake)
        return true
    }

    /// Puts Apple TV to sleep along with the TV, like the Siri Remote's power button, so nothing
    /// keeps playing to a dark screen and the next wake switches the TV on. Connects to the paired
    /// Apple TV first when needed.
    @discardableResult
    func sleepAppleTV(timeout: TimeInterval = 4) async -> Bool {
        guard await ensureConnected(timeout: timeout) else { return false }
        driver.press(.sleep)
        return true
    }

    /// Connects to the paired Apple TV if needed (never pairing) and waits for it.
    private func ensureConnected(timeout: TimeInterval) async -> Bool {
        if connected { return true }
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
        return connected
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

    func skip(forward: Bool) {
        let playback = snapshot.playback
        guard connected, forward ? playback.canSkipForward : playback.canSkipBackward else { return }
        driver.skip(forward: forward)
        notice = nil; hasError = false
    }

    /// Opens the player's info panel, as swiping down on the Siri Remote does during playback.
    func showInfo() {
        guard snapshot.playback.active else { return }
        press(.down)
    }

    /// Turns Apple TV's subtitles on or off, like the Remote app's button. The button follows
    /// Apple TV's readback; it pulses until the new setting is reported.
    func toggleSubtitles(now: Date = Date()) {
        let playback = snapshot.playback
        guard connected, playback.canToggleSubtitles else { return }
        driver.setSubtitles(!playback.subtitlesOn)
        subtitleRequest = (!playback.subtitlesOn, now)
        subtitlesPending = true
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
