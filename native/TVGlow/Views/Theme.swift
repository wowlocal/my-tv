import SwiftUI

enum GlowTheme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.060)
    static let accent = Color.white
    static let ink = Color(white: 0.96)
    static let muted = Color(white: 0.57)
    static let line = Color.white.opacity(0.08)
    static let connected = Color(red: 0.39, green: 0.83, blue: 0.57)
}

struct ConnectionBadge: View {
    let connected: Bool
    var busy = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(busy ? .orange : connected ? GlowTheme.connected : GlowTheme.muted)
                .frame(width: 5, height: 5)
            Text(busy ? "Connecting" : connected ? "Connected" : "Offline")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(GlowTheme.muted)
        .accessibilityElement(children: .combine)
    }
}

struct RemoteButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? GlowTheme.background : GlowTheme.ink)
            .background(prominent ? Color.white : Color.white.opacity(configuration.isPressed ? 0.2 : 0.085), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .opacity(configuration.isPressed && prominent ? 0.8 : 1)
    }
}

struct RoundControl: View {
    let symbol: String
    let label: String
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .frame(width: size, height: size).contentShape(Circle())
        }
        .buttonStyle(RemoteButtonStyle()).accessibilityLabel(label).help(label)
    }
}

struct DeviceMessage: View {
    let text: String
    var error = false

    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(error ? .orange : GlowTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Colors of the Remote app's controls: near-black fill with a hairline edge on pure black.
/// Used where Liquid Glass is unavailable (before iOS / macOS 26).
enum RemoteChrome {
    static let fill = Color(white: 0.06)
    static let pressed = Color(white: 0.16)
    /// The Remote app's touch surface (#1C1C1E).
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let stroke = Color.white.opacity(0.13)
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.62)
    /// Opens and closes the level bars with a rubbery bounce. `velocity` carries a released
    /// finger's speed on.
    static func reveal(velocity: Double = 0) -> Animation {
        .interpolatingSpring(duration: 0.55, bounce: 0.38, initialVelocity: velocity)
    }

    static var hasGlass: Bool {
        if #available(iOS 26.0, macOS 26.0, *) { return true }
        return false
    }
}

extension View {
    /// Liquid Glass on iOS / macOS 26 and later; the flat Remote-app chrome before that.
    @ViewBuilder
    func remoteGlass<S: Shape>(_ shape: S, interactive: Bool = false, tint: Color? = nil, pressed: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(tint ?? (pressed ? RemoteChrome.pressed : RemoteChrome.fill), in: shape)
                .overlay(shape.stroke(tint == nil ? RemoteChrome.stroke : .clear, lineWidth: 1))
        }
    }
}

/// Groups glass shapes so they blend and morph together; a plain group before iOS / macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

struct CircleButton: View {
    let symbol: String
    var diameter: CGFloat = 50
    var glyph: CGFloat? = nil
    var weight: Font.Weight = .regular
    var highlighted = false
    var pulsing = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: glyph ?? diameter * 0.36, weight: weight))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, options: .repeating, isActive: pulsing)
                .animation(.snappy(duration: 0.25), value: symbol)
                .frame(width: diameter, height: diameter).contentShape(Circle())
        }
        .buttonStyle(CircleButtonStyle(highlighted: highlighted))
    }
}

struct CircleButtonStyle: ButtonStyle {
    var highlighted = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(highlighted ? Color.black : GlowTheme.ink)
            .remoteGlass(Circle(), interactive: true, tint: highlighted ? .white : nil, pressed: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? (RemoteChrome.hasGlass ? 0.96 : 0.92) : 1)
            .animation(RemoteChrome.press, value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.25), value: highlighted)
    }
}

/// A grabber that bends into a chevron: 1 points up (pull up to open), -1 points down
/// (pull down to close), 0 is flat. Animatable, so it bends as the panel follows the finger.
struct GrabberChevron: Shape {
    var bend: Double
    var animatableData: Double {
        get { bend }
        set { bend = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let lift = rect.height / 2 * min(max(bend, -1), 1)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + lift))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - lift))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + lift))
        return path
    }
}

/// Clips only the bottom edge, so a panel can be cut off as it slides behind the buttons
/// while its glass edge and shadow still show at the sides.
struct BottomEdgeClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - 40, y: rect.minY - 40, width: rect.width + 80, height: rect.height + 40))
    }
}

/// The small white Apple TV app badge shown in the device capsule.
struct TVBadge: View {
    var body: some View {
        HStack(spacing: 0.3) {
            Image(systemName: "applelogo").font(.system(size: 5.3, weight: .bold))
            Text("tv").font(.system(size: 6.4, weight: .bold))
        }
        .foregroundStyle(.black).frame(width: 14.5, height: 14.5)
        .background(.white, in: RoundedRectangle(cornerRadius: 3.8, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A plain white glyph on the touch surface, like the Remote app's playback controls.
/// Dimmed when disabled; its tap target stays small so taps beside it still reach Apple TV.
struct PadIconButton: View {
    let symbol: String
    var pulsing = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 24.5))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, options: .repeating, isActive: pulsing)
                .animation(.snappy(duration: 0.25), value: symbol)
                .frame(width: 56, height: 50).contentShape(Rectangle())
        }
        .buttonStyle(PadIconStyle())
    }
}

struct PadIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? (configuration.isPressed ? 0.45 : 1) : 0.4))
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(RemoteChrome.press, value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.25), value: isEnabled)
    }
}

/// Faint icon buttons that live inside the touch surface.
struct SurfaceIcon: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.38)).frame(width: 44, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}
