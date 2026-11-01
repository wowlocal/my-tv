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

    /// Read from Companion's media-control flags and subtitle setting, and MRP's now-playing
    /// state; nothing is sent to build it.
    private var playback: AppleRemotePlayback {
        guard manager.connectionStatus == .connected else { return AppleRemotePlayback() }
        let mrp = manager.mrpManager
        let commands = mrp.supportedCommands
        let canSeek = commands.contains(.seekToPlaybackPosition) && mrp.nowPlaying?.elapsedTime != nil
        return AppleRemotePlayback.make(
            flags: manager.mediaControlFlags, nowPlaying: mrp.nowPlaying != nil,
            mrpSkipBackward: commands.contains(.skipBackward) || canSeek,
            mrpSkipForward: commands.contains(.skipForward) || canSeek,
            skipBackwardInterval: interval(.skipBackward), skipForwardInterval: interval(.skipForward),
            captionSetting: manager.captionSetting)
    }

    private func interval(_ command: MediaCommand) -> Double {
        guard let seconds = manager.mrpManager.preferredSkipIntervals[command], seconds > 0, seconds <= 120 else { return 10 }
        return seconds
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

    /// Toggles Apple TV's subtitle setting the way Apple's Remote app does. Unlike switching
    /// MRP language options (which muted the TV app's audio), this never touches audio.
    func toggleSubtitles() { manager.setCaptionSetting(AppleRemotePlayback.Captions.toggle) }

    func isPaired(deviceID: String) -> Bool { KeychainStorage.load(for: deviceID) != nil }

    func sendText(_ text: String) {
        manager.resetTextInputState()
        manager.updateRemoteText(text)
    }
}
