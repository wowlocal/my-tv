#if os(iOS)
import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// Turns the iPhone's volume buttons into steps while `isEnabled`: each press calls `onStep`
/// (+1 up, −1 down), then puts the phone's own volume back so the phone doesn't change.
/// A nearly invisible system volume view keeps iOS from showing its volume pop-up.
/// While disabled (Sonos offline, app in the background) the buttons work as usual.
struct HardwareVolumeButtons: UIViewRepresentable {
    var isEnabled: Bool
    let onStep: (Int) -> Void

    func makeUIView(context: Context) -> VolumeButtonView { VolumeButtonView() }

    func updateUIView(_ view: VolumeButtonView, context: Context) {
        view.onStep = onStep
        view.wantsEnabled = isEnabled
    }

    static func dismantleUIView(_ view: VolumeButtonView, coordinator: ()) {
        view.wantsEnabled = false
    }
}

final class VolumeButtonView: UIView {
    var onStep: ((Int) -> Void)?
    /// Takes effect once the view is in a window: the system volume view needs one.
    var wantsEnabled = false { didSet { update() } }

    private let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private var observation: NSKeyValueObservation?
    private var active = false
    /// The phone's volume before the remote took over the buttons; put back afterwards.
    private var original: Float?
    /// Where the phone's volume is parked between presses: one notch from either end, so a
    /// press registers in both directions.
    private var baseline: Float = 0.5
    /// The volume the phone should be at now; a change away from it is a button press.
    private var expected: Float = 0.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        volumeView.alpha = 0.01
        addSubview(volumeView)
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        update()
    }

    private func update() {
        let enable = wantsEnabled && window != nil
        guard enable != active else { return }
        enable ? start() : stop()
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Ambient and mixing: nothing playing on the phone is interrupted or ducked.
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }
        active = true
        let current = session.outputVolume
        original = current
        let notch: Float = 1 / 16
        baseline = min(max(current, notch), 1 - notch)
        expected = current
        if abs(baseline - current) > 0.001, setSystemVolume(baseline) { expected = baseline }
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            DispatchQueue.main.async { self?.volumeChanged(to: value) }
        }
    }

    private func volumeChanged(to value: Float) {
        guard active, abs(value - expected) > 0.01 else { return }  // our own reset
        onStep?(value > expected ? 1 : -1)
        expected = setSystemVolume(baseline) ? baseline : value
    }

    private func stop() {
        active = false
        observation = nil
        if let original, abs(original - expected) > 0.001 { _ = setSystemVolume(original) }
        original = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Sets the phone's volume through the system volume view's slider, the only public way.
    @discardableResult
    private func setSystemVolume(_ value: Float) -> Bool {
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return false }
        slider.value = value
        return true
    }
}
#endif
