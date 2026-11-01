import XCTest

@MainActor
final class PlaybackTests: XCTestCase {
    private typealias Flag = AppleRemotePlayback.Flag

    private func connectedStore(_ driver: MockAppleRemoteDriver, playback: AppleRemotePlayback) -> AppleRemoteStore {
        let store = AppleRemoteStore(driver: driver, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        driver.snapshot.phase = .connected
        driver.snapshot.playback = playback
        store.synchronize()
        return store
    }

    private func showPlayback(subtitlesOn: Bool = false) -> AppleRemotePlayback {
        AppleRemotePlayback(active: true, canSkipBackward: true, canSkipForward: true, canToggleSubtitles: true, subtitlesOn: subtitlesOn)
    }

    // MARK: Following the player on screen

    func testRowFollowsCompanionFlagsLikeTheRemoteApp() {
        let playing = AppleRemotePlayback.make(flags: Flag.play | Flag.pause | Flag.skipForward | Flag.skipBackward | 0x100,
                                               nowPlaying: true, mrpSkipBackward: false, mrpSkipForward: false, captionSetting: 3)
        XCTAssertTrue(playing.active)
        XCTAssertTrue(playing.canSkipBackward && playing.canSkipForward)
        XCTAssertTrue(playing.canToggleSubtitles)
        XCTAssertFalse(playing.subtitlesOn)

        // Back on the shows grid: Apple TV clears the playback bits (volume may stay), even though
        // MRP still remembers the paused episode.
        let grid = AppleRemotePlayback.make(flags: 0x100, nowPlaying: true, mrpSkipBackward: true, mrpSkipForward: true, captionSetting: 3)
        XCTAssertFalse(grid.active)
        XCTAssertFalse(grid.hasControls)
        XCTAssertFalse(grid.canSkipBackward || grid.canSkipForward || grid.canToggleSubtitles)
    }

    func testMRPStandsInUntilAppleTVSendsFlags() {
        XCTAssertTrue(AppleRemotePlayback.make(flags: nil, nowPlaying: true, mrpSkipBackward: true, mrpSkipForward: false, captionSetting: nil).active)
        let idle = AppleRemotePlayback.make(flags: nil, nowPlaying: false, mrpSkipBackward: true, mrpSkipForward: true, captionSetting: 2)
        XCTAssertFalse(idle.active)
        XCTAssertFalse(idle.canSkipBackward)
        XCTAssertFalse(idle.canToggleSubtitles)
    }

    func testSubtitlesFollowAppleTVsSetting() {
        let on = AppleRemotePlayback.make(flags: Flag.play, nowPlaying: true, mrpSkipBackward: false, mrpSkipForward: false, captionSetting: 2)
        XCTAssertTrue(on.subtitlesOn)
        XCTAssertTrue(on.canToggleSubtitles)
        XCTAssertFalse(on.canSkipForward, "no skip bit and no MRP skip")
        let unknown = AppleRemotePlayback.make(flags: Flag.play, nowPlaying: true, mrpSkipBackward: false, mrpSkipForward: false, captionSetting: nil)
        XCTAssertFalse(unknown.canToggleSubtitles, "dimmed until Apple TV reports its setting")
    }

    func testSkipSymbolsOnlyUseIntervalsSFSymbolsDraws() {
        XCTAssertEqual(AppleRemotePlayback.skipSymbol(forward: true, seconds: 10), "goforward.10")
        XCTAssertEqual(AppleRemotePlayback.skipSymbol(forward: false, seconds: 15), "gobackward.15")
        XCTAssertEqual(AppleRemotePlayback.skipSymbol(forward: true, seconds: 20), "goforward")
        XCTAssertEqual(AppleRemotePlayback.skipSymbol(forward: true, seconds: 10.5), "goforward")
    }

    // MARK: Buttons

    func testSkipIsSentOnlyWhenConnectedAndSupported() {
        let driver = MockAppleRemoteDriver()
        let store = connectedStore(driver, playback: AppleRemotePlayback(active: true, canSkipBackward: true))
        defer { store.stop() }
        store.skip(forward: true)
        store.skip(forward: false)
        XCTAssertEqual(driver.skips, [false], "unsupported forward skip is not sent")

        driver.snapshot.phase = .disconnected
        store.synchronize()
        store.skip(forward: false)
        XCTAssertEqual(driver.skips, [false], "nothing is queued while offline")
    }

    func testInfoOpensThePlayerPanelOnlyWhileSomethingPlays() {
        let driver = MockAppleRemoteDriver()
        let store = connectedStore(driver, playback: AppleRemotePlayback())
        defer { store.stop() }
        store.showInfo()
        XCTAssertTrue(driver.commands.isEmpty, "nothing loaded: no stray down press")
        driver.snapshot.playback = showPlayback()
        store.synchronize()
        store.showInfo()
        XCTAssertEqual(driver.commands, [.down])
    }

    func testSubtitleTogglePendsUntilAppleTVReportsTheNewSetting() {
        let driver = MockAppleRemoteDriver()
        let start = Date()
        let store = connectedStore(driver, playback: showPlayback(subtitlesOn: false))
        defer { store.stop() }
        store.toggleSubtitles(now: start)
        XCTAssertEqual(driver.subtitleToggles, 1)
        XCTAssertTrue(store.subtitlesPending)

        driver.snapshot.playback.subtitlesOn = true
        store.synchronize(now: start.addingTimeInterval(1))
        XCTAssertFalse(store.subtitlesPending)
        XCTAssertFalse(store.hasError)

        store.toggleSubtitles(now: start.addingTimeInterval(2))
        store.synchronize(now: start.addingTimeInterval(3))
        XCTAssertTrue(store.subtitlesPending, "still waiting for Apple TV")
        store.synchronize(now: start.addingTimeInterval(8))
        XCTAssertFalse(store.subtitlesPending)
        XCTAssertTrue(store.hasError, "a setting that never changed is reported")
    }

    func testSubtitlesAreNotSentOfflineOrBeforeAppleTVReportsItsSetting() {
        let driver = MockAppleRemoteDriver()
        var playback = showPlayback()
        playback.canToggleSubtitles = false
        let store = connectedStore(driver, playback: playback)
        defer { store.stop() }
        store.toggleSubtitles()
        XCTAssertEqual(driver.subtitleToggles, 0)

        driver.snapshot.playback = showPlayback()
        driver.snapshot.phase = .disconnected
        store.synchronize()
        store.toggleSubtitles()
        XCTAssertEqual(driver.subtitleToggles, 0)
    }
}
