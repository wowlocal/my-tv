import Foundation
import SwiftUI

/// Springs the level panel to rest from where the finger let go, carrying the finger's real speed
/// (reveal progress per second). A fast flick runs on into the rubber band and springs back,
/// in proportion to its speed, instead of stopping dead at the end. Evaluated frame by frame, so
/// a new drag can catch the panel mid-flight exactly where it is.
///
/// SwiftUI's `interpolatingSpring(initialVelocity:)` measures velocity relative to the distance
/// left, which can't carry speed released at (or past) the resting place; `Spring.value(target:
/// initialVelocity:time:)` takes it in absolute units.
struct RevealSettle: Equatable {
    let start: Date
    let from: Double
    let to: Double
    /// Progress per second when the finger let go; positive opens.
    let velocity: Double
    var bounce = 0.3

    private var spring: Spring { Spring(duration: 0.5, bounce: bounce) }
    private func elapsed(_ date: Date) -> TimeInterval { max(0, date.timeIntervalSince(start)) }

    func value(at date: Date) -> Double {
        from + spring.value(target: to - from, initialVelocity: velocity, time: elapsed(date))
    }

    /// Resting: close enough and slow enough that the last frames wouldn't show.
    func isFinished(at date: Date) -> Bool {
        let time = elapsed(date)
        guard time < 3 else { return true }
        let offset = value(at: date) - to
        let speed = spring.velocity(target: to - from, initialVelocity: velocity, time: time)
        return time > 0.05 && abs(offset) < 0.0015 && abs(speed) < 0.02
    }
}
