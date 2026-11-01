import XCTest

@MainActor
final class MockWakeSender: TVWakeSending {
    var sent: [(String, String)] = []
    var probes = 0
    var reachable = true
    var failure = false
    func send(host: String, mac: String) throws {
        if failure { throw ControlError.device("Wake packet could not be sent.") }
        sent.append((host, mac))
    }
    func isReachable(host: String) async -> Bool { probes += 1; return reachable }
}

final class TVPowerTests: XCTestCase {
    @MainActor
    func testMagicPacketHasSixFFBytesAndSixteenCopiesOfTVMAC() async throws {
        let bytes = Array(try WakeOnLAN.packet(mac: "74:e6:b8:2d:7f:2c"))
        XCTAssertEqual(bytes.count, 102)
        XCTAssertEqual(Array(bytes.prefix(6)), Array(repeating: 0xff, count: 6))
        for index in 0..<16 {
            XCTAssertEqual(Array(bytes[(6 + index * 6)..<(12 + index * 6)]), [0x74, 0xe6, 0xb8, 0x2d, 0x7f, 0x2c])
        }
        XCTAssertEqual(try WakeOnLAN.packet(mac: "74-E6-B8-2D-7F-2C"), Data(bytes))
        for invalid in ["", "74:E6:B8:2D:7F", "74:E6:B8:2D:7F:XYZ", "00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "75:E6:B8:2D:7F:2C"] {
            XCTAssertThrowsError(try WakeOnLAN.packet(mac: invalid))
        }
    }

    @MainActor
    func testPowerOffRequiresConnectionAndDoesNotChangeBrightnessOrSonos() async {
        let tv = MockTV(), sonos = MockSonos(), wake = MockWakeSender()
        let store = ControlStore(tv: tv, sonos: sonos, vault: MemoryPairing(), wakeSender: wake, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.turnOffTV()
        XCTAssertEqual(tv.powerOffs, 0)
        await store.connectTV()
        await store.connectSonos()
        await store.turnOffTV()
        XCTAssertEqual(tv.powerOffs, 1)
        XCTAssertFalse(store.tvConnected)
        XCTAssertNil(store.brightness)
        XCTAssertFalse(store.tvError)
        XCTAssertTrue(store.sonosConnected)
        XCTAssertTrue(tv.written.isEmpty)
        XCTAssertTrue(sonos.written.isEmpty)
        XCTAssertTrue(sonos.muteWrites.isEmpty)
        XCTAssertTrue(wake.sent.isEmpty)
    }

    @MainActor
    func testRejectedPowerOffKeepsConnectionAndReportsUnconfirmedCommand() async {
        let tv = MockTV()
        let store = ControlStore(tv: tv, sonos: MockSonos(), vault: MemoryPairing(), wakeSender: MockWakeSender(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.connectTV()
        tv.powerFailure = true
        await store.turnOffTV()
        XCTAssertTrue(store.tvConnected)
        XCTAssertEqual(store.brightness, 0)
        XCTAssertTrue(store.tvError)
        XCTAssertTrue(store.tvMessage.contains("not confirmed"))
        XCTAssertFalse(store.tvPowerBusy)
    }

    @MainActor
    func testWakeReconnectsByReadingAndOptionallyWakesAppleTV() async {
        let tv = MockTV(), wake = MockWakeSender(), pairing = MemoryPairing()
        pairing.keys["192.168.2.159"] = "test-key"
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ControlStore(tv: tv, sonos: MockSonos(), vault: pairing, wakeSender: wake, defaults: defaults)
        var appleWakes = 0
        await store.turnOnTV { appleWakes += 1 }
        XCTAssertEqual(wake.sent.count, 1)
        XCTAssertEqual(wake.sent.first?.0, "192.168.2.159")
        XCTAssertEqual(wake.probes, 1)
        XCTAssertEqual(appleWakes, 1)
        XCTAssertTrue(store.tvConnected)
        XCTAssertEqual(store.brightness, 0)
        XCTAssertTrue(tv.written.isEmpty)
        XCTAssertEqual(tv.powerOffs, 0)
        store.wakeWithAppleTV = false
        await store.turnOnTV { appleWakes += 1 }
        XCTAssertEqual(appleWakes, 1)
        XCTAssertFalse(defaults.bool(forKey: "wakeWithAppleTV"))
    }

    @MainActor
    func testUnpairedWakeDoesNotStartPairingOrClaimTVIsOn() async {
        let tv = MockTV(), wake = MockWakeSender()
        let store = ControlStore(tv: tv, sonos: MockSonos(), vault: MemoryPairing(), wakeSender: wake, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.turnOnTV()
        XCTAssertEqual(wake.sent.count, 1)
        XCTAssertEqual(wake.probes, 0)
        XCTAssertFalse(store.tvConnected)
        XCTAssertNil(store.brightness)
        XCTAssertTrue(store.tvMessage.contains("Connect TV"))
    }

    @MainActor
    func testPairedTVReconnectsOnlyWhenReachableAndOnlyReads() async {
        let tv = MockTV(), wake = MockWakeSender(), pairing = MemoryPairing()
        let unpaired = ControlStore(tv: tv, sonos: MockSonos(), vault: MemoryPairing(), wakeSender: wake, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await unpaired.reconnectTVIfPaired()
        XCTAssertEqual(wake.probes, 0, "An unpaired TV must wait for an explicit Connect")
        XCTAssertFalse(unpaired.tvConnected)

        pairing.keys["192.168.2.159"] = "test-key"
        let store = ControlStore(tv: tv, sonos: MockSonos(), vault: pairing, wakeSender: wake, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        wake.reachable = false
        await store.reconnectTVIfPaired()
        XCTAssertEqual(wake.probes, 1)
        XCTAssertFalse(store.tvConnected)
        XCTAssertFalse(store.tvError)

        wake.reachable = true
        await store.reconnectTVIfPaired()
        XCTAssertTrue(store.tvConnected)
        XCTAssertEqual(store.brightness, 0)
        XCTAssertTrue(tv.written.isEmpty)
        XCTAssertEqual(tv.powerOffs, 0)
        XCTAssertTrue(wake.sent.isEmpty)
    }

    @MainActor
    func testWakeStillUsesAppleTVWhenNetworkWakeCannotBeSent() async {
        let wake = MockWakeSender()
        wake.failure = true
        let store = ControlStore(tv: MockTV(), sonos: MockSonos(), vault: MemoryPairing(), wakeSender: wake, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var appleWakes = 0
        await store.turnOnTV { appleWakes += 1 }
        XCTAssertEqual(appleWakes, 1)
        XCTAssertFalse(store.tvError)
        await store.turnOnTV()
        XCTAssertTrue(store.tvError)
    }

    @MainActor
    func testInvalidWakeConfigurationSendsNothingToEitherDevice() async {
        let tv = MockTV(), wake = MockWakeSender()
        let store = ControlStore(tv: tv, sonos: MockSonos(), vault: MemoryPairing(), wakeSender: wake, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var appleWakes = 0
        store.tvMAC = "invalid"
        await store.turnOnTV { appleWakes += 1 }
        XCTAssertTrue(wake.sent.isEmpty)
        XCTAssertEqual(appleWakes, 0)
        XCTAssertTrue(store.tvError)
        XCTAssertFalse(store.tvPowerBusy)
    }

    func testPowerPressWaitsUntilTVGlowKnowsWhetherTheTVIsOn() {
        XCTAssertTrue(PowerToggle.isReady(tvConnecting: false, tvConnected: true, appleTVConnected: false), "a TV that answers is on: turn it off")
        XCTAssertTrue(PowerToggle.isReady(tvConnecting: false, tvConnected: false, appleTVConnected: true), "TV silent, Apple TV ready to wake it")
        XCTAssertFalse(PowerToggle.isReady(tvConnecting: true, tvConnected: false, appleTVConnected: true), "still finding out whether the TV is on")
        XCTAssertFalse(PowerToggle.isReady(tvConnecting: false, tvConnected: false, appleTVConnected: false), "no way to turn it on yet")
    }
}
