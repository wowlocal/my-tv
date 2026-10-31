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
            canSubmitPIN: manager.canSubmitPIN, keyboardFocused: manager.keyboardFocused
        )
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

    func isPaired(deviceID: String) -> Bool { KeychainStorage.load(for: deviceID) != nil }

    func sendText(_ text: String) {
        manager.resetTextInputState()
        manager.updateRemoteText(text)
    }
}
