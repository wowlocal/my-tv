import Foundation

/// Frame delivery during an animation, from the intervals between display refreshes. At 120 Hz a
/// frame is due every 8.33 ms; a longer gap means the main thread missed one or more frames.
struct FrameStats: Equatable {
    var frames = 0
    var duration = 0.0
    /// Frames per second actually delivered.
    var fps = 0.0
    /// Share of intervals within 25 % of the target (one refresh at 120 Hz).
    var onTime = 0.0
    /// Refreshes that came and went without a new frame.
    var dropped = 0
    /// Intervals longer than 1.5 refreshes.
    var hitches = 0
    var worstMs = 0.0
    var p99Ms = 0.0

    init() {}

    init(intervals: [Double], targetFPS: Double = 120) {
        guard !intervals.isEmpty, targetFPS > 0 else { return }
        let target = 1 / targetFPS
        frames = intervals.count
        duration = intervals.reduce(0, +)
        fps = duration > 0 ? Double(frames) / duration : 0
        onTime = Double(intervals.filter { $0 <= target * 1.25 }.count) / Double(frames)
        dropped = intervals.reduce(0) { $0 + max(0, Int(($1 / target).rounded()) - 1) }
        hitches = intervals.filter { $0 > target * 1.5 }.count
        let sorted = intervals.sorted()
        worstMs = (sorted.last ?? 0) * 1000
        p99Ms = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.99).rounded(.down)))] * 1000
    }

    var summary: String {
        String(format: "%d frames in %.2f s: %.1f fps, %.1f%% on time, %d dropped, %d hitches, p99 %.1f ms, worst %.1f ms",
               frames, duration, fps, onTime * 100, dropped, hitches, p99Ms, worstMs)
    }
}
