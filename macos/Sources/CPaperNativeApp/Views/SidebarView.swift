import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SidebarAppHeader(model: model)

            VStack(spacing: 6) {
                ForEach(AppRoute.allCases) { route in
                    SidebarRouteRow(route: route, isSelected: model.route == route) {
                        model.route = route
                        if route == .downloads {
                            Task { await model.refreshDownloads() }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("常用科目")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await model.addSelectedSubjectToFavorites() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedSubject == nil || model.isSelectedSubjectFavorite || !model.backendState.isAvailable)
                    .help("添加当前科目")
                }
                .padding(.horizontal, CPDesign.Spacing.sm)

                if model.favorites.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("暂无常用科目")
                            .font(.callout.weight(.medium))
                        Text("在搜索页选择科目后点收藏，这里会变成快捷入口。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.035))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }
                } else {
                    ForEach(model.favorites) { subject in
                        FavoriteSubjectRow(model: model, subject: subject)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color.accentColor.opacity(0.07),
                    Color(red: 0.80, green: 0.88, blue: 1.0).opacity(0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .navigationTitle("C-Paper")
        .navigationSplitViewColumnWidth(min: 224, ideal: 248, max: 288)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.favorites)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.route)
    }
}

private struct SidebarAppHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("C-Paper")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.backendState == .connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(model.backendState.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(model.backendState.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            }
        }
        .padding(.bottom, 2)
    }
}

private struct FavoriteSubjectRow: View {
    @Bindable var model: AppModel
    let subject: Subject
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.selectFavorite(subject)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "star")
                        .font(.system(size: 14))
                        .frame(width: 18, alignment: .center)
                        .foregroundStyle(.secondary)
                    Text(subject.displayName)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.removeFavorite(subject) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(isHovering ? 1 : 0)
            .accessibilityHidden(!isHovering)
            .help("移除收藏")
        }
        .padding(.horizontal, CPDesign.Spacing.sm)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.20) : Color.clear)
        }
        .onHover { isHovering = $0 }
    }
}

private struct SidebarRouteRow: View {
    let route: AppRoute
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: route.symbolName)
                    .font(.system(size: 15, weight: isSelected ? .medium : .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 20, height: 20, alignment: .center)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(route.title)
                    .font(.callout.weight(isSelected ? .medium : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 38)
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.58) : Color.primary.opacity(0))
                .shadow(color: isSelected ? Color.accentColor.opacity(0.12) : .clear, radius: 12, x: 0, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: 20)
                    .padding(.leading, 2)
            }
        }
    }
}
