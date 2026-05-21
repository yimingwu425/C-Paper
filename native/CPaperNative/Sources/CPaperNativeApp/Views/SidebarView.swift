import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            VStack(spacing: 2) {
                ForEach(AppRoute.allCases) { route in
                    SidebarRouteRow(route: route, isSelected: model.route == route) {
                        model.route = route
                        if route == .downloads {
                            Task { await model.refreshDownloads() }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: CPDesign.Spacing.sm) {
                HStack {
                    Text("常用科目")
                        .font(.caption)
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
                    Text("暂无常用科目")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, CPDesign.Spacing.sm)
                        .padding(.top, 2)
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
        .padding(.top, 18)
        .background(.bar)
        .navigationTitle("C-Paper")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.favorites)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.route)
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
        .padding(.vertical, 3)
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
            .frame(height: 30)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.065 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .stroke(Color.secondary.opacity(isSelected ? 0.12 : 0), lineWidth: 1)
        }
    }
}
