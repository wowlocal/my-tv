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

    func testAppleTVKeychainServiceIsAlsoIsolatedFromUpstreamAndProduction() async {
        let release = KeychainStorage.serviceIdentifier(for: "com.anna.tvglow.mac")
        let debug = KeychainStorage.serviceIdentifier(for: "com.anna.tvglow.mac.debug")
        XCTAssertNotEqual(release, debug)
        XCTAssertEqual(debug, "com.anna.tvglow.mac.debug.appletv.credentials")
        XCTAssertNotEqual(release, "com.itsytv.credentials")
    }
}
