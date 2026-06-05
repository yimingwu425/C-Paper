import SwiftUI

struct PaperComponentGroup: Identifiable {
    let id: String
    let files: [PaperFile]

    var title: String {
        files.first?.componentTitle ?? "Other"
    }

    var detail: String {
        let types = files.compactMap(\.paperType)
        if types.isEmpty {
            return "\(files.count) 个文件"
        }
        return "\(types.joined(separator: " + ")) · \(files.count) 个文件"
    }
}

struct PaperGroupHeader: View {
    let group: PaperComponentGroup

    var body: some View {
        HStack(spacing: CPDesign.Spacing.sm) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(group.title)
                .font(.headline)
            Text(group.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct PaperRow: View {
    let file: PaperFile
    let onPreview: () -> Void
    let onDownload: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: CPDesign.Spacing.sm) {
            Image(systemName: file.paperType == "MS" ? "checklist" : "doc.text")
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(file.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 6) {
                PaperRowActionButton(
                    title: "预览",
                    systemImage: "eye",
                    isVisible: isHovering,
                    action: onPreview
                )
                PaperRowActionButton(
                    title: "下载",
                    systemImage: "arrow.down.circle",
                    isVisible: isHovering,
                    action: onDownload
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .fill(hoverFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .stroke(.quaternary.opacity(isHovering ? 0.65 : 0), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
        .scaleEffect(isHovering && !reduceMotion ? 1.004 : 1)
        .animation(CPDesign.Motion.tactile(reduceMotion: reduceMotion), value: isHovering)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onPreview)
    }

    private var hoverFill: Color {
        guard isHovering else { return .clear }
        return colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.035)
    }
}

private struct PaperRowActionButton: View {
    let title: String
    let systemImage: String
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.accentColor.opacity(isVisible ? 0.12 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct WorkflowEmptyState: View {
    let title: String
    let systemImage: String
    let steps: [String]

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 78, height: 78)
                Circle()
                    .stroke(Color.white.opacity(0.44), lineWidth: 1)
                    .frame(width: 78, height: 78)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text("按下面顺序操作，列表会在这里更新。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 7) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20, height: 20)
                            .background {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.14))
                            }
                        Text(step)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.50))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.accentColor.opacity(0.10), lineWidth: 1)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 640)
    }
}
