import SwiftUI

struct GlassSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(CPDesign.Spacing.md)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: CPDesign.Radius.panel, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CPDesign.Radius.panel, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
    }
}
