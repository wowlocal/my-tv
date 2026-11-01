import XCTest
import ItsytvCore

final class RemoteTouchNavigationTests: XCTestCase {
    func testTapSelectsAndSmallPointerMovementIsTolerated() {
        var navigation = RemoteTouchNavigation()
        XCTAssertNil(navigation.move(x: 3, y: -2))
        XCTAssertEqual(navigation.end(x: 3, y: -2), .select)
    }

    func testSwipesFollowDominantAxisAndRepeatAfterFurtherMovement() {
        var navigation = RemoteTouchNavigation()
        XCTAssertNil(navigation.move(x: 20, y: 4))
        XCTAssertEqual(navigation.move(x: 35, y: 8), .right)
        XCTAssertNil(navigation.move(x: 50, y: 8))
        XCTAssertEqual(navigation.move(x: 70, y: 8), .right)
        XCTAssertEqual(navigation.move(x: 70, y: -30), .up)
        XCTAssertEqual(navigation.move(x: 30, y: -30), .left)
        XCTAssertEqual(navigation.move(x: 30, y: 10), .down)
        XCTAssertNil(navigation.end(x: 30, y: 10))
    }

    func testDraggingBackToOriginDoesNotSelect() {
        var navigation = RemoteTouchNavigation()
        XCTAssertEqual(navigation.move(x: -40, y: 0), .left)
        XCTAssertEqual(navigation.move(x: 0, y: 0), .right)
        XCTAssertNil(navigation.end(x: 0, y: 0))
        XCTAssertEqual(navigation.end(x: 0, y: 0), .select)
    }

    func testShortDragDoesNotAccidentallySelect() {
        var navigation = RemoteTouchNavigation()
        XCTAssertNil(navigation.move(x: 18, y: 2))
        XCTAssertNil(navigation.end(x: 0, y: 0))
        XCTAssertNil(navigation.end(x: 20, y: 0))
    }

    func testResetDiscardsInterruptedGesture() {
        var navigation = RemoteTouchNavigation()
        XCTAssertEqual(navigation.move(x: 40, y: 0), .right)
        navigation.reset()
        XCTAssertNil(navigation.move(x: 2, y: 0))
        XCTAssertEqual(navigation.end(x: 2, y: 0), .select)
    }
}

final class LevelDragTests: XCTestCase {
    func testTapNeverChangesTheLevel() {
        var drag = LevelDrag()
        XCTAssertNil(drag.move(dx: 0, dy: 0, width: 200, current: 30))
        XCTAssertNil(drag.move(dx: 3, dy: 2, width: 200, current: 30))
        XCTAssertFalse(drag.end())
    }

    func testVerticalSwipeIsIgnoredForTheWholeTouch() {
        var drag = LevelDrag()
        XCTAssertNil(drag.move(dx: 2, dy: -20, width: 200, current: 30))
        XCTAssertEqual(drag.state, .ignored)
        XCTAssertNil(drag.move(dx: 120, dy: -20, width: 200, current: 30), "Turning sideways later does not adjust")
        XCTAssertFalse(drag.end())
        XCTAssertEqual(drag.state, .idle)
    }

    func testSidewaysDragFollowsTheFingerWithoutJumping() {
        var drag = LevelDrag()
        XCTAssertEqual(drag.move(dx: 10, dy: 2, width: 200, current: 40), 40, "Crossing the slop does not jump")
        XCTAssertEqual(drag.move(dx: 60, dy: 5, width: 200, current: 99), 65, "Relative to the start level, not the readback")
        XCTAssertEqual(drag.move(dx: 60, dy: 90, width: 200, current: 40), 65, "Vertical drift while adjusting is fine")
        XCTAssertTrue(drag.end())
    }

    func testLevelsStayInRange() {
        var drag = LevelDrag()
        _ = drag.move(dx: -10, dy: 0, width: 200, current: 20)
        XCTAssertEqual(drag.move(dx: -200, dy: 0, width: 200, current: 20), 0)
        XCTAssertTrue(drag.end())
        _ = drag.move(dx: 10, dy: 0, width: 200, current: 90)
        XCTAssertEqual(drag.move(dx: 400, dy: 0, width: 200, current: 90), 100)
        XCTAssertTrue(drag.end())
    }

    func testUnknownWidthNeverAdjusts() {
        var drag = LevelDrag()
        XCTAssertNil(drag.move(dx: 40, dy: 0, width: 0, current: 50))
        XCTAssertFalse(drag.end())
    }
}

@MainActor
final class MockAppleRemoteDriver: AppleRemoteDriving {
    var snapshot = AppleRemoteSnapshot(devices: [.init(id: "tv", name: "tv", model: "AppleTV14,1")])
    var scans = 0
    var connections: [String] = []
    var disconnections = 0
    var pins: [String] = []
    var commands: [AppleRemoteCommand] = []
    var texts: [String] = []
    func startDiscovery() { scans += 1 }
    func stopDiscovery() {}
    func connect(deviceID: String) { connections.append(deviceID); snapshot.phase = .connecting }
    func disconnect() { disconnections += 1; snapshot.phase = .disconnected; snapshot.canSubmitPIN = false }
    func submitPIN(_ pin: String) { pins.append(pin) }
    func press(_ command: AppleRemoteCommand) { commands.append(command) }
    func sendText(_ text: String) { texts.append(text) }
    var paired: Set<String> = []
    var pairedLookups = 0
    func isPaired(deviceID: String) -> Bool { pairedLookups += 1; return paired.contains(deviceID) }
}

@MainActor
final class AppleRemoteTests: XCTestCase {
    private func store(_ driver: MockAppleRemoteDriver) -> AppleRemoteStore {
        AppleRemoteStore(driver: driver, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testOpeningOnlyDiscoversWithoutConnectingOrSendingCommands() async {
        let driver = MockAppleRemoteDriver()
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.start()
        underTest.start()
        XCTAssertEqual(driver.scans, 1)
        XCTAssertEqual(underTest.selectedDeviceID, "tv")
        XCTAssertTrue(driver.connections.isEmpty)
        XCTAssertTrue(driver.commands.isEmpty)
        XCTAssertTrue(driver.pins.isEmpty)
    }

    func testOfflineButtonsAreIgnoredInsteadOfQueued() async {
        let driver = MockAppleRemoteDriver()
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.synchronize()
        underTest.press(.home)
        underTest.connect()
        underTest.press(.playPause)
        XCTAssertEqual(driver.connections, ["tv"])
        XCTAssertTrue(driver.commands.isEmpty)
        driver.snapshot.phase = .connected
        underTest.synchronize()
        underTest.press(.left)
        XCTAssertEqual(driver.commands, [.left])
    }

    func testPINRequiresFourASCIIDigits() async {
        XCTAssertEqual(AppleRemoteStore.validPIN(" 1234 "), "1234")
        for invalid in ["", "123", "12345", "12a4", "１２３４", "1 234"] {
            XCTAssertNil(AppleRemoteStore.validPIN(invalid))
        }
    }

    func testPINWaitsForChallengeAndCannotBeSubmittedTwice() async {
        let driver = MockAppleRemoteDriver()
        let remote = store(driver)
        defer { remote.stop() }
        driver.snapshot.phase = .pairing
        remote.synchronize()
        remote.pin = "1234"
        remote.submitPIN()
        XCTAssertTrue(driver.pins.isEmpty)
        driver.snapshot.canSubmitPIN = true
        remote.synchronize()
        remote.submitPIN()
        remote.submitPIN()
        XCTAssertEqual(driver.pins, ["1234"])
        driver.snapshot.phase = .connected
        remote.synchronize()
        XCTAssertEqual(remote.pin, "")
    }

    func testKeyboardOnlySendsToFocusedTVTextField() async {
        let driver = MockAppleRemoteDriver()
        let underTest = store(driver)
        defer { underTest.stop() }
        driver.snapshot.phase = .connected
        underTest.synchronize()
        underTest.text = "Movie title"
        underTest.sendText()
        XCTAssertTrue(driver.texts.isEmpty)
        driver.snapshot.keyboardFocused = true
        underTest.synchronize()
        underTest.sendText()
        XCTAssertEqual(driver.texts, ["Movie title"])
        XCTAssertEqual(underTest.text, "")
    }

    func testConnectionTimeoutStopsPendingSession() async {
        let driver = MockAppleRemoteDriver()
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.synchronize()
        underTest.connect()
        underTest.synchronize(now: Date().addingTimeInterval(26))
        XCTAssertEqual(driver.disconnections, 1)
        XCTAssertEqual(underTest.snapshot.phase, .disconnected)
        XCTAssertTrue(underTest.hasError)
        XCTAssertTrue(driver.commands.isEmpty)
    }

    func testPairedAppleTVConnectsAutomaticallyWithoutSendingCommands() async {
        let driver = MockAppleRemoteDriver()
        driver.paired = ["tv"]
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.start()
        XCTAssertEqual(driver.connections, ["tv"])
        XCTAssertTrue(driver.commands.isEmpty)
        XCTAssertTrue(driver.pins.isEmpty)
        driver.snapshot.phase = .connected
        underTest.synchronize()
        XCTAssertTrue(underTest.connected)
        XCTAssertTrue(driver.commands.isEmpty)
    }

    func testAutomaticConnectionNeverStartsPINPairing() async {
        let driver = MockAppleRemoteDriver()
        driver.paired = ["tv"]
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.start()
        XCTAssertEqual(driver.connections, ["tv"])
        // Credentials turned out to be missing: the TV asks for a code. Cancel instead.
        driver.snapshot.phase = .pairing
        underTest.synchronize()
        XCTAssertEqual(driver.disconnections, 1)
        XCTAssertEqual(underTest.snapshot.phase, .disconnected)
        XCTAssertFalse(underTest.hasError)
        underTest.synchronize(now: Date().addingTimeInterval(120))
        XCTAssertEqual(driver.connections, ["tv"])
        XCTAssertTrue(driver.pins.isEmpty)
    }

    func testFailedAutomaticConnectionRetriesWithBackoffAndDisconnectStopsIt() async {
        let driver = MockAppleRemoteDriver()
        driver.paired = ["tv"]
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.start()
        driver.snapshot.phase = .failed("Network unreachable")
        underTest.synchronize()
        XCTAssertEqual(driver.connections, ["tv"])
        underTest.synchronize(now: Date().addingTimeInterval(61))
        XCTAssertEqual(driver.connections, ["tv", "tv"])
        driver.snapshot.phase = .connected
        underTest.synchronize()
        underTest.disconnect()
        underTest.synchronize(now: Date().addingTimeInterval(600))
        XCTAssertEqual(driver.connections, ["tv", "tv"])
        XCTAssertTrue(driver.commands.isEmpty)
    }

    func testUnpairedAppleTVIsCheckedOnceAndNeverConnectedAutomatically() async {
        let driver = MockAppleRemoteDriver()
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.start()
        for minutes in 1...5 { underTest.synchronize(now: Date().addingTimeInterval(Double(minutes) * 60)) }
        XCTAssertTrue(driver.connections.isEmpty)
        XCTAssertEqual(driver.pairedLookups, 1)
    }

    func testWakeConnectsPairedAppleTVThenSendsWake() async throws {
        let driver = MockAppleRemoteDriver()
        driver.paired = ["tv"]
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.synchronize()
        let waking = Task { await underTest.wake(timeout: 3) }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(driver.connections, ["tv"])
        XCTAssertTrue(driver.commands.isEmpty)
        driver.snapshot.phase = .connected
        let woke = await waking.value
        XCTAssertTrue(woke)
        XCTAssertEqual(driver.commands, [.wake])
    }

    func testWakeWithoutPairedAppleTVDoesNothing() async {
        let driver = MockAppleRemoteDriver()
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.synchronize()
        let woke = await underTest.wake(timeout: 1)
        XCTAssertFalse(woke)
        XCTAssertTrue(driver.connections.isEmpty)
        XCTAssertTrue(driver.commands.isEmpty)
    }

    func testAppleTVKeychainServiceIsAlsoIsolatedFromUpstreamAndProduction() async {
        let release = KeychainStorage.serviceIdentifier(for: "com.anna.tvglow.mac")
        let debug = KeychainStorage.serviceIdentifier(for: "com.anna.tvglow.mac.debug")
        XCTAssertNotEqual(release, debug)
        XCTAssertEqual(debug, "com.anna.tvglow.mac.debug.appletv.credentials")
        XCTAssertNotEqual(release, "com.itsytv.credentials")
    }
}
