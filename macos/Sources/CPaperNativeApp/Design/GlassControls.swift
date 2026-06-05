import SwiftUI

struct GlassInputShell<Content: View>: View {
    let systemImage: String?
    let isFocused: Bool
    let content: Content
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    init(systemImage: String? = nil, isFocused: Bool = false, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.isFocused = isFocused
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconStyle)
                    .frame(width: 18, alignment: .center)
            }
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
        .background(.thinMaterial, in: shape)
        .background {
            shape.fill(Color.primary.opacity(fillOpacity))
        }
        .overlay {
            shape.stroke(strokeColor, lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.48)
        .contentShape(shape)
        .onHover { isHovering = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
    }

    private var fillOpacity: Double {
        if isFocused { return 0.075 }
        if isHovering { return 0.055 }
        return 0.030
    }

    private var strokeColor: Color {
        if isFocused { return Color.accentColor.opacity(0.42) }
        if isHovering { return Color.accentColor.opacity(0.24) }
        return Color.secondary.opacity(0.16)
    }

    private var iconStyle: AnyShapeStyle {
        isFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
    }
}

struct GlassTextField: View {
    let placeholder: String
    let systemImage: String?
    @Binding var text: String
    @FocusState private var isFocused: Bool

    init(_ placeholder: String, text: Binding<String>, systemImage: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.systemImage = systemImage
    }

    var body: some View {
        GlassInputShell(systemImage: systemImage, isFocused: isFocused) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
        }
    }
}

struct GlassMenuField<Selection: Hashable, MenuContent: View, LabelContent: View>: View {
    @Binding var selection: Selection
    let systemImage: String?
    let menuContent: MenuContent
    let labelContent: LabelContent

    init(
        selection: Binding<Selection>,
        systemImage: String? = nil,
        @ViewBuilder menuContent: () -> MenuContent,
        @ViewBuilder label: () -> LabelContent
    ) {
        self._selection = selection
        self.systemImage = systemImage
        self.menuContent = menuContent()
        self.labelContent = label()
    }

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                menuContent
            }
            .labelsHidden()
        } label: {
            GlassInputShell(systemImage: systemImage) {
                HStack(spacing: 8) {
                    labelContent
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
