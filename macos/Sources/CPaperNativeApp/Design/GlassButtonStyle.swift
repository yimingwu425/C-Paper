import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    let prominence: CPDesign.GlassButtonProminence

    init(_ prominence: CPDesign.GlassButtonProminence = .normal) {
        self.prominence = prominence
    }

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, prominence: prominence)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let prominence: CPDesign.GlassButtonProminence

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)

        configuration.label
            .font(.subheadline.weight(prominence == .primary ? .semibold : .regular))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundMaterial, in: shape)
            .background {
                shape
                    .fill(tintColor.opacity(fillOpacity))
            }
            .overlay {
                shape
                    .strokeBorder(.white.opacity(isHovering ? 0.22 : 0.12), lineWidth: 1)
                    .blendMode(.overlay)
            }
            .overlay {
                shape
                    .stroke(.quaternary.opacity(0.58), lineWidth: 1)
            }
            .shadow(color: tintColor.opacity(shadowOpacity), radius: isHovering ? 5 : 1, x: 0, y: isHovering ? 2 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(CPDesign.Motion.tactile(reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(CPDesign.Motion.gentle(reduceMotion: reduceMotion), value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var backgroundMaterial: Material {
        switch prominence {
        case .primary:
            return .thinMaterial
        case .subtle, .normal, .destructive:
            return .ultraThinMaterial
        }
    }

    private var tintColor: Color {
        switch prominence {
        case .primary:
            return .accentColor
        case .destructive:
            return .red
        case .subtle, .normal:
            return .primary
        }
    }

    private var fillOpacity: Double {
        guard isEnabled else { return 0.03 }
        switch prominence {
        case .primary:
            return configuration.isPressed ? 0.24 : (isHovering ? 0.20 : 0.16)
        case .destructive:
            return configuration.isPressed ? 0.16 : (isHovering ? 0.12 : 0.07)
        case .normal:
            return configuration.isPressed ? 0.10 : (isHovering ? 0.07 : 0.035)
        case .subtle:
            return configuration.isPressed ? 0.06 : (isHovering ? 0.035 : 0.012)
        }
    }

    private var shadowOpacity: Double {
        guard isEnabled else { return 0 }
        switch prominence {
        case .primary:
            return isHovering ? 0.10 : 0.05
        case .destructive:
            return isHovering ? 0.07 : 0.02
        case .normal, .subtle:
            return isHovering ? 0.04 : 0.01
        }
    }

    private var foregroundStyle: some ShapeStyle {
        switch prominence {
        case .primary:
            return AnyShapeStyle(.primary)
        case .destructive:
            return AnyShapeStyle(Color.red)
        case .subtle, .normal:
            return AnyShapeStyle(.primary)
        }
    }
}
