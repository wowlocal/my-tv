import XCTest

@MainActor
final class PlaybackTests: XCTestCase {
    private let english = SubtitleTrack(id: "en", name: "English", languageTag: "en")
    private let german = SubtitleTrack(id: "de", name: "Deutsch", languageTag: "de-DE")

    private func connectedStore(_ driver: MockAppleRemoteDriver, playback: AppleRemotePlayback,
                                defaults: UserDefaults = UserDefaults(suiteName: UUID().uuidString)!) -> AppleRemoteStore {
        let store = AppleRemoteStore(driver: driver, defaults: defaults)
        driver.snapshot.phase = .connected
        driver.snapshot.playback = playback
        store.synchronize()
        return store
    }

    private func showPlayback(subtitleID: String? = nil) -> AppleRemotePlayback {
        AppleRemotePlayback(active: true, canSkipBackward: true, canSkipForward: true,
                            subtitles: [english, german], subtitleID: subtitleID)
    }

    // MARK: Row visibility

    func testRowOnlyAppearsWhileSomethingWithControlsIsLoaded() {
        XCTAssertFalse(AppleRemotePlayback().hasControls)
        XCTAssertFalse(AppleRemotePlayback(active: true).hasControls, "music without skip or subtitles shows no row")
        XCTAssertFalse(AppleRemotePlayback(active: false, canSkipForward: true).hasControls)
        XCTAssertTrue(AppleRemotePlayback(active: true, canSkipBackward: true).hasControls)
        XCTAssertTrue(AppleRemotePlayback(active: true, subtitles: [english]).hasControls)
    }

    func testSkipSymbolsOnlyUseIntervalsSFSymbolsDraws() {
        XCTAssertEqual(AppleRemotePlayback.skipSymbol(forward: true, seconds: 10), "goforward.10")
        XCTAssertEqual(AppleRemotePlayback.skipSymbol(forward: false, seconds: 15), "gobackward.15")
        XCTAssertEqual(AppleRemotePlayback.skipSymbol(forward: true, seconds: 20), "goforward")
        XCTAssertEqual(AppleRemotePlayback.skipSymbol(forward: true, seconds: 10.5), "goforward")
    }

    // MARK: Skipping

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

    // MARK: Subtitles

    func testTurningSubtitlesOnPrefersTheLanguagePickedLastTime() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let driver = MockAppleRemoteDriver()
        let store = connectedStore(driver, playback: showPlayback(subtitleID: "de"), defaults: defaults)
        defer { store.stop() }
        store.selectSubtitle(nil)
        XCTAssertEqual(driver.subtitleCommands, [nil])

        driver.snapshot.playback.subtitleID = nil
        store.synchronize()
        store.selectSubtitle("de")
        driver.snapshot.playback.subtitleID = "de"
        store.synchronize()
        driver.snapshot.playback.subtitleID = nil
        store.synchronize()
        store.toggleSubtitles()
        XCTAssertEqual(driver.subtitleCommands, [nil, "de", "de"])
    }

    func testToggleTurnsSubtitlesOffWhenOn() {
        let driver = MockAppleRemoteDriver()
        let store = connectedStore(driver, playback: showPlayback(subtitleID: "en"))
        defer { store.stop() }
        store.toggleSubtitles()
        XCTAssertEqual(driver.subtitleCommands, [nil])
    }

    func testPendingStateFollowsReadbackAndReportsAnUnchangedPlayer() {
        let driver = MockAppleRemoteDriver()
        let start = Date()
        let store = connectedStore(driver, playback: showPlayback())
        defer { store.stop() }
        store.selectSubtitle("en", now: start)
        XCTAssertTrue(store.subtitlesPending)
        store.selectSubtitle("en", now: start)
        XCTAssertEqual(driver.subtitleCommands, ["en", "en"], "a repeat tap re-sends; nothing is queued")

        driver.snapshot.playback.subtitleID = "en"
        store.synchronize(now: start.addingTimeInterval(1))
        XCTAssertFalse(store.subtitlesPending)
        XCTAssertFalse(store.hasError)

        store.selectSubtitle(nil, now: start.addingTimeInterval(2))
        store.synchronize(now: start.addingTimeInterval(3))
        XCTAssertTrue(store.subtitlesPending, "still waiting for Apple TV")
        store.synchronize(now: start.addingTimeInterval(8))
        XCTAssertFalse(store.subtitlesPending)
        XCTAssertTrue(store.hasError, "a player that ignored the change is reported")
    }

    func testSubtitlesAreNotSentOfflineOrForUnknownTracks() {
        let driver = MockAppleRemoteDriver()
        let store = connectedStore(driver, playback: showPlayback())
        defer { store.stop() }
        store.selectSubtitle("fr")
        XCTAssertTrue(driver.subtitleCommands.isEmpty)
        store.selectSubtitle(nil)
        XCTAssertTrue(driver.subtitleCommands.isEmpty, "already off")
        driver.snapshot.phase = .disconnected
        store.synchronize()
        store.toggleSubtitles()
        XCTAssertTrue(driver.subtitleCommands.isEmpty)
    }

    // MARK: Choosing tracks

    func testChoiceOrder() {
        let tracks = [german, english]
        XCTAssertEqual(SubtitleChoice.choose(from: tracks, preferredTag: "de-DE", defaultID: "en", languages: ["en-US"])?.id, "de")
        XCTAssertEqual(SubtitleChoice.choose(from: tracks, preferredTag: "de", defaultID: "en", languages: ["en-US"])?.id, "de",
                       "a picked language matches regional variants")
        XCTAssertEqual(SubtitleChoice.choose(from: tracks, preferredTag: nil, defaultID: "de", languages: ["en-GB"])?.id, "en")
        XCTAssertEqual(SubtitleChoice.choose(from: tracks, preferredTag: nil, defaultID: "en", languages: ["ja"])?.id, "en")
        XCTAssertEqual(SubtitleChoice.choose(from: tracks, preferredTag: nil, defaultID: nil, languages: ["ja"])?.id, "de")
        XCTAssertNil(SubtitleChoice.choose(from: [], preferredTag: "en", defaultID: nil, languages: ["en"]))
    }

    // MARK: Reading the player's language options

    private let audioEN = LanguageOptionInfo(id: "a-en", type: nil, languageTag: "en", displayName: "English")
    private let audioDE = LanguageOptionInfo(id: "a-de", type: 0, languageTag: "de", displayName: "Deutsch")
    private let subEN = LanguageOptionInfo(id: "s-en", type: 1, languageTag: "en", displayName: "English CC",
                                           characteristics: ["public.accessibility.transcribes-spoken-dialog"])
    private let subDE = LanguageOptionInfo(id: "s-de", type: 1, languageTag: "de", displayName: "Deutsch")
    private let forced = LanguageOptionInfo(id: "s-forced", type: 1, languageTag: "en", displayName: "English Forced",
                                            characteristics: [LanguageOptionInfo.forcedOnly])

    private var groups: [LanguageGroupInfo] {
        [LanguageGroupInfo(allowsEmptySelection: false, defaultID: "a-en", options: [audioEN, audioDE]),
         LanguageGroupInfo(allowsEmptySelection: true, defaultID: "s-de", options: [subEN, forced, subDE])]
    }

    func testOnlySubtitleTracksAreOfferedAndAudioIsNever() {
        let resolved = SubtitleChoice.resolve(groups: groups, current: [audioEN])
        XCTAssertEqual(resolved.tracks.map(\.id), ["s-en", "s-de"], "audio and forced-only tracks are left out")
        XCTAssertEqual(resolved.tracks.first?.name, "English CC")
        XCTAssertNil(resolved.enabledID)
        XCTAssertEqual(resolved.defaultID, "s-de")
    }

    func testForcedSubtitlesDoNotCountAsOn() {
        XCTAssertNil(SubtitleChoice.resolve(groups: groups, current: [audioEN, forced]).enabledID)
        XCTAssertEqual(SubtitleChoice.resolve(groups: groups, current: [audioDE, subDE]).enabledID, "s-de")
    }

    func testAudioIsNeverTreatedAsSubtitlesEvenInAGroupThatAllowsNoSelection() {
        // Regression: an audio group marked allowsEmptySelection made the sound track look like
        // subtitles, so "subtitles off" disabled the audio.
        let audioGroup = LanguageGroupInfo(allowsEmptySelection: true, defaultID: "a-en", options: [audioEN, audioDE])
        let resolved = SubtitleChoice.resolve(groups: [audioGroup], current: [audioEN])
        XCTAssertTrue(resolved.tracks.isEmpty)
        XCTAssertNil(resolved.enabledID)
        XCTAssertNil(resolved.defaultID)
        XCTAssertTrue(SubtitleChoice.shownSubtitles(in: [audioEN, audioDE]).isEmpty, "turning subtitles off never touches audio")
        XCTAssertEqual(SubtitleChoice.shownSubtitles(in: [audioEN, subDE, forced]).map(\.id), ["s-de"])
    }

    func testOnlyExplicitlyLegibleOptionsAreSubtitles() {
        let untyped = LanguageOptionInfo(id: "x", type: nil, languageTag: "fr")
        XCTAssertTrue(SubtitleChoice.resolve(groups: [LanguageGroupInfo(allowsEmptySelection: true, options: [untyped])], current: [untyped]).tracks.isEmpty)
        XCTAssertEqual(SubtitleChoice.resolve(groups: [LanguageGroupInfo(allowsEmptySelection: false, options: [subDE])], current: []).tracks.map(\.id), ["s-de"])
        let mixed = LanguageGroupInfo(options: [audioEN, subEN])
        XCTAssertEqual(SubtitleChoice.resolve(groups: [mixed], current: [audioEN]).tracks.map(\.id), ["s-en"])
        XCTAssertNil(SubtitleChoice.resolve(groups: [mixed], current: [audioEN]).enabledID)
    }

    func testTrackNamesFallBackToTheLanguage() {
        let unnamed = LanguageOptionInfo(id: "n", type: 1, languageTag: "fr")
        let name = SubtitleChoice.resolve(groups: [LanguageGroupInfo(options: [unnamed])], current: []).tracks.first?.name
        XCTAssertEqual(name, Locale.current.localizedString(forIdentifier: "fr"))
    }
}
