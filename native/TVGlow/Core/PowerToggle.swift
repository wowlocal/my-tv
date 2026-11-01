import Foundation

/// When a TV Power press from outside the app (Action button, Control Center) can act. On a cold
/// launch nothing is connected yet, and "toggle" needs to know whether the TV is on. A TV that
/// answers is on, so it gets turned off. Otherwise TV Glow waits for the TV's connection attempt
/// to finish and for Apple TV, which turns the TV on over HDMI-CEC (iOS blocks Wake-on-LAN
/// broadcasts). After `timeout` it acts anyway with what it knows.
enum PowerToggle {
    static let timeout: TimeInterval = 6

    static func isReady(tvConnecting: Bool, tvConnected: Bool, appleTVConnected: Bool) -> Bool {
        tvConnected || (!tvConnecting && appleTVConnected)
    }
}
