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

final class FrameStatsTests: XCTestCase {
    func testSteady120HzIsAllOnTime() {
        let stats = FrameStats(intervals: Array(repeating: 1 / 120, count: 120))
        XCTAssertEqual(stats.fps, 120, accuracy: 0.01)
        XCTAssertEqual(stats.onTime, 1)
        XCTAssertEqual(stats.dropped, 0)
        XCTAssertEqual(stats.hitches, 0)
        XCTAssertEqual(stats.worstMs, 1000 / 120, accuracy: 0.001)
    }

    func testSixtyHzCountsEveryOtherRefreshAsDropped() {
        let stats = FrameStats(intervals: Array(repeating: 1 / 60, count: 60))
        XCTAssertEqual(stats.fps, 60, accuracy: 0.01)
        XCTAssertEqual(stats.onTime, 0)
        XCTAssertEqual(stats.dropped, 60)
        XCTAssertEqual(stats.hitches, 60)
    }

    func testOneLongFrameShowsAsAHitch() {
        let stats = FrameStats(intervals: Array(repeating: 1 / 120, count: 99) + [4 / 120])
        XCTAssertEqual(stats.dropped, 3)
        XCTAssertEqual(stats.hitches, 1)
        XCTAssertEqual(stats.worstMs, 4000 / 120, accuracy: 0.001)
        XCTAssertEqual(stats.onTime, 0.99, accuracy: 0.0001)
        XCTAssertEqual(FrameStats(intervals: []), FrameStats())
    }
}

final class RevealDragTests: XCTestCase {
    func testSettleCarriesTheFlickIntoTheRubberBandAndSpringsBack() {
        let start = Date()
        // Released right at "open" while still moving up fast: no distance left, but real speed.
        let flick = RevealSettle(start: start, from: 1, to: 1, velocity: 12)
        let peak = (1...40).map { flick.value(at: start.addingTimeInterval(Double($0) / 120)) }.max() ?? 1
        XCTAssertGreaterThan(peak, 1.2, "overshoots past open, so the panel stretches like rubber")
        XCTAssertFalse(flick.isFinished(at: start.addingTimeInterval(0.1)))
        XCTAssertTrue(flick.isFinished(at: start.addingTimeInterval(2.5)))
        XCTAssertEqual(flick.value(at: start.addingTimeInterval(2.5)), 1, accuracy: 0.002, "and comes back to rest")

        let gentle = RevealSettle(start: start, from: 1, to: 1, velocity: 3)
        let gentlePeak = (1...40).map { gentle.value(at: start.addingTimeInterval(Double($0) / 120)) }.max() ?? 1
        XCTAssertLessThan(gentlePeak, peak, "a slower flick stretches less: speed matters")
    }

    func testSettleStartsExactlyWhereTheFingerLetGo() {
        let start = Date()
        let settle = RevealSettle(start: start, from: 0.42, to: 0, velocity: -2)
        XCTAssertEqual(settle.value(at: start), 0.42, accuracy: 0.0001)
        XCTAssertLessThan(settle.value(at: start.addingTimeInterval(1 / 60)), 0.42, "keeps moving the finger's way")
        let calm = RevealSettle(start: start, from: 0, to: 1, velocity: 0, bounce: 0)
        let samples = (0...240).map { calm.value(at: start.addingTimeInterval(Double($0) / 120)) }
        XCTAssertLessThanOrEqual(samples.max() ?? 0, 1.0001, "Reduce Motion: no overshoot")
    }

    func testPanelFollowsTheFingerOneToOne() {
        var drag = RevealDrag()
        XCTAssertEqual(drag.progress(from: 0, dy: -30, height: 100), 0.3, accuracy: 0.0001)
        XCTAssertEqual(drag.progress(from: 1, dy: -55, height: 100), 0.55, accuracy: 0.0001, "The start is kept for the whole drag")
        XCTAssertEqual(drag.progress(from: 0, dy: -130, height: 100), 1.3, accuracy: 0.0001, "Overswipe past open")
        XCTAssertEqual(drag.progress(from: 0, dy: 40, height: 100), -0.4, accuracy: 0.0001, "Overswipe past closed")
        XCTAssertEqual(drag.progress(from: 0, dy: -300, height: 100), 3, accuracy: 0.0001, "A hard pull keeps stretching; the rubber band gives the resistance")
        XCTAssertEqual(drag.progress(from: 0, dy: -900, height: 100), 5, "Bounded far beyond the rubber band's limit")
        XCTAssertTrue(drag.isDragging)
    }

    func testOverswipeGivesLikeRubber() {
        let open = RevealGeometry(reveal: 1, height: 100)
        XCTAssertEqual(open.space, 100)
        XCTAssertEqual(open.stretch, 0)
        XCTAssertEqual(open.drop, 0)
        let half = RevealGeometry(reveal: 0.5, height: 100)
        XCTAssertEqual(half.space, 50)
        XCTAssertEqual(half.progress, 0.5)

        let pulled = RevealGeometry(reveal: 1.3, height: 100)
        XCTAssertEqual(pulled.space, 100)
        XCTAssertGreaterThan(pulled.stretch, 0)
        XCTAssertLessThan(pulled.stretch, 30, "Resists: less than the finger's 30 pt")
        let further = RevealGeometry(reveal: 2, height: 100)
        XCTAssertGreaterThan(further.stretch, pulled.stretch)
        XCTAssertLessThan(further.stretch, RevealGeometry.stretchLimit)

        let dropped = RevealGeometry(reveal: -0.4, height: 100)
        XCTAssertEqual(dropped.space, 0)
        XCTAssertEqual(dropped.progress, 0)
        XCTAssertGreaterThan(dropped.drop, 0)
        XCTAssertLessThan(dropped.drop, RevealGeometry.dropLimit)
        XCTAssertEqual(RevealGeometry.rubber(10, limit: 0), 0)
    }

    func testSlowPartialDragSpringsBack() {
        var drag = RevealDrag()
        _ = drag.progress(from: 0, dy: -30, height: 100)
        let result = drag.end(at: 0.3, predictedDY: -35, velocityDY: -40, height: 100)
        XCTAssertFalse(result.open)
        XCTAssertEqual(result.velocity, 0.4, accuracy: 0.0001, "The finger's own speed, even when it settles the other way")
        XCTAssertFalse(drag.isDragging)
    }

    func testShortFlickOpensWithTheFingersSpeed() {
        var drag = RevealDrag()
        _ = drag.progress(from: 0, dy: -20, height: 100)
        let result = drag.end(at: 0.2, predictedDY: -60, velocityDY: -200, height: 100)
        XCTAssertTrue(result.open)
        XCTAssertEqual(result.velocity, 2, accuracy: 0.0001, "Absolute: 200 pt/s over a 100 pt panel")
        _ = drag.progress(from: 0, dy: -20, height: 100)
        XCTAssertEqual(drag.end(at: 0.2, predictedDY: -300, velocityDY: -2500, height: 100).velocity, 25, accuracy: 0.0001,
                       "A fast flick keeps its speed instead of being throttled")
        _ = drag.progress(from: 0, dy: -20, height: 100)
        XCTAssertEqual(drag.end(at: 0.2, predictedDY: -300, velocityDY: -9000, height: 100).velocity, 30, "Only absurd speeds are capped")
    }

    func testDraggingAnOpenPanelPastHalfwayCloses() {
        var drag = RevealDrag()
        XCTAssertEqual(drag.progress(from: 1, dy: 70, height: 100), 0.3, accuracy: 0.0001)
        let result = drag.end(at: 0.3, predictedDY: 80, velocityDY: 100, height: 100)
        XCTAssertFalse(result.open)
        XCTAssertEqual(result.velocity, -1, accuracy: 0.0001)
    }

    func testUnknownHeightNeverMovesThePanel() {
        var drag = RevealDrag()
        XCTAssertEqual(drag.progress(from: 1, dy: 80, height: 0), 1)
        XCTAssertEqual(drag.end(at: 1, predictedDY: 300, velocityDY: 900, height: 0).open, true)
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
    var skips: [Bool] = []
    var subtitleRequests: [Bool] = []
    func skip(forward: Bool) { skips.append(forward) }
    func setSubtitles(_ on: Bool) { subtitleRequests.append(on) }
    func sendText(_ text: String) { texts.append(text) }
    /// Answers to attentionState(), in order; nil once used up.
    var attentionStates: [Int?] = []
    func attentionState() async -> Int? { attentionStates.isEmpty ? nil : attentionStates.removeFirst() }
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

    func testAwakeAppleTVIsPutToSleepFirstSoWakingSwitchesTheTVOn() async {
        // TV switched off on its own while Apple TV stayed awake: a bare wake would do nothing.
        let driver = MockAppleRemoteDriver()
        driver.snapshot.phase = .connected
        driver.attentionStates = [3, 3, 1]
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.synchronize()
        let woke = await underTest.wake(timeout: 1, sleepTimeout: 2, poll: 0.01)
        XCTAssertTrue(woke)
        XCTAssertEqual(driver.commands, [.sleep, .wake])
    }

    func testSleepingAppleTVIsWokenDirectly() async {
        let driver = MockAppleRemoteDriver()
        driver.snapshot.phase = .connected
        driver.attentionStates = [1]
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.synchronize()
        let woke = await underTest.wake(timeout: 1, sleepTimeout: 2, poll: 0.01)
        XCTAssertTrue(woke)
        XCTAssertEqual(driver.commands, [.wake])
    }

    func testWakeStillFollowsWhenAppleTVNeverReportsSleep() async {
        let driver = MockAppleRemoteDriver()
        driver.snapshot.phase = .connected
        driver.attentionStates = [3]
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.synchronize()
        let woke = await underTest.wake(timeout: 1, sleepTimeout: 0.1, poll: 0.01)
        XCTAssertTrue(woke)
        XCTAssertEqual(driver.commands, [.sleep, .wake])
    }

    func testSleepAppleTVNeedsAPairedAppleTV() async {
        let driver = MockAppleRemoteDriver()
        let underTest = store(driver)
        defer { underTest.stop() }
        underTest.synchronize()
        let slept = await underTest.sleepAppleTV(timeout: 0.5)
        XCTAssertFalse(slept)
        XCTAssertTrue(driver.commands.isEmpty)
        driver.snapshot.phase = .connected
        underTest.synchronize()
        let sleptNow = await underTest.sleepAppleTV(timeout: 0.5)
        XCTAssertTrue(sleptNow)
        XCTAssertEqual(driver.commands, [.sleep])
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
