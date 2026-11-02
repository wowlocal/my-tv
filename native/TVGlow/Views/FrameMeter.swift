#if DEBUG && os(iOS)
import QuartzCore
import os

/// Debug-only: measures frame delivery while an animation runs. A display link asking for 120 Hz
/// records every refresh it gets; when the main thread is too busy to render a frame in time,
/// refreshes are missed and the intervals grow. `nextFrame()` lets a self-test move the UI exactly
/// once per refresh, the way a finger's touches arrive.
@MainActor
final class FrameMeter: NSObject {
    static let log = Logger(subsystem: "com.anna.tvglow", category: "Perf")

    private var link: CADisplayLink?
    private var timestamps: [CFTimeInterval] = []
    private var waiter: CheckedContinuation<CFTimeInterval, Never>?
    /// Frames the drawer's own TimelineView rendered during the measurement: its natural rate.
    var drawerFrames = 0
    var isRunning: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        timestamps = []
        drawerFrames = 0
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        timestamps.append(link.timestamp)
        waiter?.resume(returning: link.timestamp)
        waiter = nil
    }

    /// Waits for the next refresh and returns its timestamp.
    func nextFrame() async -> CFTimeInterval {
        await withCheckedContinuation { waiter = $0 }
    }

    /// Stops and logs what was measured.
    @discardableResult
    func stop(_ label: String) -> FrameStats {
        link?.invalidate()
        link = nil
        waiter?.resume(returning: 0)
        waiter = nil
        let intervals = zip(timestamps.dropFirst(), timestamps).map { $0 - $1 }
        let stats = FrameStats(intervals: intervals)
        let drawerFPS = stats.duration > 0 ? Double(drawerFrames) / stats.duration : 0
        let line = "PERF \(label): \(stats.summary); drawer rendered \(String(format: "%.1f", drawerFPS)) fps"
        Self.log.notice("\(line, privacy: .public)")
        print(line)  // also on stdout, for `devicectl device process launch --console`
        return stats
    }
}
#endif
