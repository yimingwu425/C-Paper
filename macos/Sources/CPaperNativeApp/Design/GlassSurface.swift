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
