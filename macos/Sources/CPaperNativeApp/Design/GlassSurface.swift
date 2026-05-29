import SwiftUI

struct GlassSurface<Content: View>: View {
    private let content: Content
    private let role: CPDesign.SurfaceRole
    private let padding: CGFloat
    private let strokeOpacity: Double

    init(
        role: CPDesign.SurfaceRole = .content,
        padding: CGFloat = CPDesign.Spacing.md,
        strokeOpacity: Double = 0.55,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.role = role
        self.padding = padding
        self.strokeOpacity = strokeOpacity
    }

    var body: some View {
        content
            .padding(padding)
            .liquidGlassSurface(role, strokeOpacity: strokeOpacity)
    }
}

struct LiquidGlassSurfaceModifier: ViewModifier {
    let role: CPDesign.SurfaceRole
    let strokeOpacity: Double
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: role.radius, style: .continuous)

        content
            .background(role.material, in: shape)
            .background {
                shape
                    .fill(.background.opacity(fillOpacity))
            }
            .overlay(alignment: .top) {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.34 * strokeOpacity),
                                .white.opacity(0.06 * strokeOpacity),
                                .black.opacity(0.08 * strokeOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .blendMode(.overlay)
            }
            .overlay {
                shape
                    .stroke(.quaternary.opacity(strokeOpacity), lineWidth: 1)
            }
            .shadow(color: .black.opacity(role.shadowOpacity), radius: role == .floating || role == .modal ? 18 : 10, x: 0, y: role == .control ? 2 : 8)
    }

    private var fillOpacity: Double {
        switch (role, colorScheme) {
        case (.base, .light):
            return 0.12
        case (.base, .dark):
            return 0.18
        case (.floating, .light):
            return 0.14
        case (.floating, .dark):
            return 0.20
        case (.modal, .light):
            return 0.10
        case (.modal, .dark):
            return 0.16
        case (.control, .light):
            return 0.08
        case (.control, .dark):
            return 0.12
        case (.content, .light):
            return 0.08
        case (.content, .dark):
            return 0.14
        @unknown default:
            return 0.10
        }
    }
}

extension View {
    func liquidGlassSurface(_ role: CPDesign.SurfaceRole = .content, strokeOpacity: Double = 0.55) -> some View {
        modifier(LiquidGlassSurfaceModifier(role: role, strokeOpacity: strokeOpacity))
    }

    func nativeContentBackground() -> some View {
        background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor).opacity(0.42),
                        Color(nsColor: .windowBackgroundColor).opacity(0.22),
                        Color(nsColor: .underPageBackgroundColor).opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
    }
}

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

struct StatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color
    var prominence: Prominence = .normal

    enum Prominence {
        case normal
        case tinted
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .background {
                Capsule()
                    .fill(tint.opacity(tintOpacity))
            }
            .overlay {
                Capsule()
                    .stroke(tint.opacity(strokeOpacity), lineWidth: 1)
            }
    }

    private var tintOpacity: Double {
        switch prominence {
        case .normal:
            return 0.05
        case .tinted:
            return 0.10
        }
    }

    private var strokeOpacity: Double {
        switch prominence {
        case .normal:
            return 0.22
        case .tinted:
            return 0.28
        }
    }
}

struct HeaderCount: View {
    let value: Int
    let unit: String

    var body: some View {
        Text("\(value) \(unit)")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

struct CompactPillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.caption.weight(.medium))
                .foregroundStyle(configuration.isOn ? .primary : .secondary)
                .frame(minWidth: 28)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isOn ? 0.070 : 0.025))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                        .stroke(configuration.isOn ? Color.accentColor.opacity(0.26) : Color.secondary.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
