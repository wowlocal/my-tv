import XCTest

@MainActor
final class MockTV: TVCommunicating {
    var powerOffs = 0
    var powerFailure = false
    var value = 0
    var written: [Int] = []
    var refuseWrite = false
    func connect(host: String, key: String?, awaitingApproval: @escaping () -> Void) async throws -> String { "test-key" }
    func brightness() async throws -> Int { value }
    func setBrightness(_ value: Int) async throws { written.append(value); if !refuseWrite { self.value = value } }
    func powerOff() async throws { if powerFailure { throw ControlError.disconnected }; powerOffs += 1 }
    func disconnect() {}
}

@MainActor
final class MockSonos: SonosCommunicating {
    var current = SonosState(volume: 45, muted: false)
    var written: [Int] = []
    var muteWrites: [Bool] = []
    func identify(host: String) async throws -> String { "Sonos Arc Ultra" }
    func state(host: String) async throws -> SonosState { current }
    /// Simulated network time for a volume write.
    var delay: UInt64 = 0
    func setVolume(_ volume: Int, host: String) async throws {
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        written.append(volume); current = SonosState(volume: volume, muted: current.muted)
    }
    func setMuted(_ muted: Bool, host: String) async throws {
        muteWrites.append(muted); current = SonosState(volume: current.volume, muted: muted)
    }
}

final class MemoryPairing: PairingStoring {
    var keys: [String: String] = [:]
    func key(for host: String) -> String? { keys[host] }
    func save(_ key: String, for host: String) throws { keys[host] = key }
    func remove(for host: String) { keys.removeValue(forKey: host) }
}

final class ControlTests: XCTestCase {
    func testDebugAndReleaseKeychainNamespacesAreIsolated() {
        let release = PairingStore(bundleIdentifier: "com.anna.tvglow.mac")
        let debug = PairingStore(bundleIdentifier: "com.anna.tvglow.mac.debug")
        XCTAssertEqual(release.service, "com.anna.tvglow.mac.pairing")
        XCTAssertEqual(debug.service, "com.anna.tvglow.mac.debug.pairing")
        XCTAssertNotEqual(release.service, debug.service)
        XCTAssertNotEqual(debug.service, "com.anna.tvglow.pairing")
    }

    func testOnlyPrivateAddressesAreAccepted() throws {
        XCTAssertEqual(try LocalAddress.validated("192.168.2.159"), "192.168.2.159")
        XCTAssertEqual(try LocalAddress.validated(" 10.0.0.7 "), "10.0.0.7")
        for input in ["127.0.0.1", "0.0.0.0", "8.8.8.8", "192.168.2.159:3000", "192.168.002.159", "172.32.0.2", "192.168.0.999", "example.com"] {
            XCTAssertThrowsError(try LocalAddress.validated(input), input)
        }
    }

    func testBrightnessAcceptsZeroAndNumericStrings() throws {
        XCTAssertEqual(try LocalAddress.level(NSNumber(value: 0)), 0)
        XCTAssertEqual(try LocalAddress.level("45"), 45)
        for invalid in [true, 101, -1, 22.5, "unknown"] as [Any] { XCTAssertThrowsError(try LocalAddress.level(invalid)) }
    }

    func testSonosXMLIsParsedWithNamespaces() throws {
        let xml = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:GetVolumeResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"><CurrentVolume>45</CurrentVolume></u:GetVolumeResponse></s:Body></s:Envelope>"
        XCTAssertEqual(try XMLValues.parse(Data(xml.utf8))["CurrentVolume"], "45")
    }

    @MainActor
    func testConnectingReadsLevelsWithoutChangingEitherDevice() async {
        let tv = MockTV(), sonos = MockSonos(), pairing = MemoryPairing()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ControlStore(tv: tv, sonos: sonos, vault: pairing, defaults: defaults)
        await store.connectTV()
        await store.connectSonos()
        XCTAssertEqual(store.brightness, 0)
        XCTAssertEqual(store.volume, 45)
        XCTAssertTrue(store.tvConnected)
        XCTAssertTrue(store.sonosConnected)
        XCTAssertTrue(tv.written.isEmpty)
        XCTAssertTrue(sonos.written.isEmpty)
        XCTAssertTrue(sonos.muteWrites.isEmpty)
        XCTAssertEqual(pairing.key(for: "192.168.2.159"), "test-key")
    }

    @MainActor
    func testBrightnessUsesReadbackAndReportsRejectedChanges() async {
        let tv = MockTV()
        let store = ControlStore(tv: tv, sonos: MockSonos(), vault: MemoryPairing(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.connectTV()
        await store.setBrightness(0)
        XCTAssertEqual(tv.written, [0])
        XCTAssertFalse(store.tvError)
        tv.refuseWrite = true
        await store.setBrightness(5)
        XCTAssertTrue(store.tvError)
        XCTAssertEqual(store.brightness, 0)
        XCTAssertEqual(store.brightnessDraft, 0)
    }

    @MainActor
    func testVolumeAndMuteAreIndependentOfTV() async {
        let tv = MockTV(), sonos = MockSonos()
        let store = ControlStore(tv: tv, sonos: sonos, vault: MemoryPairing(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.connectSonos()
        await store.setVolume(44)
        await store.toggleMute()
        XCTAssertEqual(store.volume, 44)
        XCTAssertTrue(store.muted)
        XCTAssertEqual(sonos.written, [44])
        XCTAssertTrue(tv.written.isEmpty)
        await store.setVolume(101)
        XCTAssertEqual(sonos.written, [44])
    }

    @MainActor
    func testVolumeReleasedWhileApplyingIsQueuedNotDropped() async throws {
        let sonos = MockSonos()
        sonos.delay = 200_000_000
        let store = ControlStore(tv: MockTV(), sonos: sonos, vault: MemoryPairing(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.connectSonos()
        let first = Task { await store.setVolume(40) }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(store.applyingVolume)
        await store.setVolume(38)
        await store.setVolume(35)
        await first.value
        XCTAssertEqual(sonos.written, [40, 35], "Only the latest queued level is applied")
        XCTAssertEqual(store.volume, 35)
        XCTAssertEqual(store.volumeDraft, 35)
        XCTAssertFalse(store.applyingVolume)
    }

    @MainActor
    func testReadbackDoesNotMoveAHeldVolumeBar() async throws {
        let sonos = MockSonos()
        sonos.delay = 200_000_000
        let store = ControlStore(tv: MockTV(), sonos: sonos, vault: MemoryPairing(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.connectSonos()
        let applying = Task { await store.setVolume(40) }
        try await Task.sleep(nanoseconds: 50_000_000)
        store.editingVolume = true
        store.volumeDraft = 30
        await applying.value
        XCTAssertEqual(store.volume, 40)
        XCTAssertEqual(store.volumeDraft, 30, "The bar stays under the finger")
        store.editingVolume = false
        await store.refresh()
        XCTAssertEqual(store.volumeDraft, 40, "Once released, readback shows the device level again")
    }
}
