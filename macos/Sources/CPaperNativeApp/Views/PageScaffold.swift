import SwiftUI

struct ScrollableWorkflowPage<Content: View>: View {
    private let content: (CGSize) -> Content

    init(@ViewBuilder content: @escaping (CGSize) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content(geometry.size)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(34)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
    }
}
