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
enum RemoteChrome {
    static let fill = Color(white: 0.06)
    static let pressed = Color(white: 0.16)
    static let stroke = Color.white.opacity(0.13)
}

struct CircleButton: View {
    let symbol: String
    var diameter: CGFloat = 50
    var glyph: CGFloat? = nil
    var weight: Font.Weight = .regular
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: glyph ?? diameter * 0.36, weight: weight))
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
            .background(highlighted ? Color.white : configuration.isPressed ? RemoteChrome.pressed : RemoteChrome.fill, in: Circle())
            .overlay(Circle().strokeBorder(highlighted ? .clear : RemoteChrome.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The small white Apple TV app badge shown in the device capsule.
struct TVBadge: View {
    var body: some View {
        HStack(spacing: 0.5) {
            Image(systemName: "applelogo").font(.system(size: 7.5, weight: .bold))
            Text("tv").font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.black).frame(width: 21, height: 21)
        .background(.white, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
        .accessibilityHidden(true)
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
