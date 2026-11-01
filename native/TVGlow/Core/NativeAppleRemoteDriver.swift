import Foundation
import ItsytvCore

@MainActor
final class NativeAppleRemoteDriver: AppleRemoteDriving {
    private let manager = AppleTVManager()

    var snapshot: AppleRemoteSnapshot {
        let phase: AppleRemotePhase
        switch manager.connectionStatus {
        case .disconnected: phase = .disconnected
        case .connecting: phase = .connecting
        case .pairing: phase = .pairing
        case .connected: phase = .connected
        case .error(let text): phase = .failed(text)
        }
        return AppleRemoteSnapshot(
            devices: manager.discoveredDevices.map { AppleRemoteDevice(id: $0.id, name: $0.name, model: $0.modelName) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            phase: phase, connectedName: manager.connectedDeviceName,
            canSubmitPIN: manager.canSubmitPIN, keyboardFocused: manager.keyboardFocused,
            playback: playback
        )
    }

    /// Read from MRP's now-playing state; nothing is sent to build it.
    private var playback: AppleRemotePlayback {
        let mrp = manager.mrpManager
        guard manager.connectionStatus == .connected, let nowPlaying = mrp.nowPlaying else { return AppleRemotePlayback() }
        let commands = mrp.supportedCommands
        let canSeek = commands.contains(.seekToPlaybackPosition) && nowPlaying.elapsedTime != nil
        var playback = AppleRemotePlayback(active: true)
        playback.canSkipBackward = commands.contains(.skipBackward) || canSeek
        playback.canSkipForward = commands.contains(.skipForward) || canSeek
        playback.skipBackwardInterval = interval(.skipBackward)
        playback.skipForwardInterval = interval(.skipForward)
        if let options = mrp.languageOptions {
            let resolved = SubtitleChoice.resolve(groups: options.available.map(Self.group), current: options.current.map(Self.info))
            playback.subtitles = resolved.tracks
            playback.subtitleID = resolved.enabledID
            playback.defaultSubtitleID = resolved.defaultID
        }
        return playback
    }

    private func interval(_ command: MediaCommand) -> Double {
        guard let seconds = manager.mrpManager.preferredSkipIntervals[command], seconds > 0, seconds <= 120 else { return 10 }
        return seconds
    }

    private static func key(_ option: MediaLanguageOption) -> String {
        option.identifier ?? "\(option.type ?? 0)|\(option.languageTag ?? "")|\(option.displayName ?? "")"
    }

    private static func info(_ option: MediaLanguageOption) -> LanguageOptionInfo {
        LanguageOptionInfo(id: key(option), type: option.type.map(Int.init), languageTag: option.languageTag,
                           displayName: option.displayName, characteristics: option.characteristics)
    }

    private static func group(_ group: MediaLanguageOptionGroup) -> LanguageGroupInfo {
        LanguageGroupInfo(allowsEmptySelection: group.allowsEmptySelection, defaultID: group.defaultOption.map(key),
                          options: group.options.map(info))
    }

    func startDiscovery() { manager.startScanning() }
    func stopDiscovery() { manager.stopScanning() }
    func connect(deviceID: String) {
        guard let device = manager.discoveredDevices.first(where: { $0.id == deviceID }) else { return }
        manager.connect(to: device)
    }
    func disconnect() { manager.disconnect() }
    func submitPIN(_ pin: String) { manager.submitPIN(pin) }

    func press(_ command: AppleRemoteCommand) {
        let button: CompanionButton
        switch command {
        case .up: button = .up
        case .down: button = .down
        case .left: button = .left
        case .right: button = .right
        case .select: button = .select
        case .back: button = .menu
        case .home: button = .home
        case .playPause: button = .playPause
        case .wake: button = .wake
        }
        manager.pressButton(button)
    }

    func skip(forward: Bool) {
        let mrp = manager.mrpManager
        let command: MediaCommand = forward ? .skipForward : .skipBackward
        let seconds = interval(command)
        if mrp.supportedCommands.contains(command) {
            mrp.sendSkip(command, interval: Float(seconds))
        } else if let nowPlaying = mrp.nowPlaying, mrp.supportedCommands.contains(.seekToPlaybackPosition) {
            // Some players only take absolute seeks.
            var target = nowPlaying.currentPosition + (forward ? seconds : -seconds)
            if let duration = nowPlaying.duration, duration > 0 { target = min(target, duration) }
            mrp.seekToPosition(max(0, target))
        }
    }

    func enableSubtitle(id: String) {
        guard let option = manager.mrpManager.languageOptions?.available.flatMap(\.options).first(where: { Self.key($0) == id }),
              Self.info(option).isLegible else { return }
        manager.mrpManager.setLanguageOption(option, enabled: true)
    }

    func disableSubtitles() {
        guard let current = manager.mrpManager.languageOptions?.current else { return }
        let shown = Set(SubtitleChoice.shownSubtitles(in: current.map(Self.info)).map(\.id))
        for option in current where shown.contains(Self.key(option)) {
            manager.mrpManager.setLanguageOption(option, enabled: false)
        }
    }

    func isPaired(deviceID: String) -> Bool { KeychainStorage.load(for: deviceID) != nil }

    func sendText(_ text: String) {
        manager.resetTextInputState()
        manager.updateRemoteText(text)
    }
}
