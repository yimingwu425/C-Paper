import SwiftUI

struct ProductBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.62),
                Color(red: 0.77, green: 0.84, blue: 1.0).opacity(0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(red: 0.47, green: 0.58, blue: 1.0).opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 120, y: -150)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color(red: 0.45, green: 0.83, blue: 0.94).opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -160, y: 140)
        }
    }
}

struct PageHero<Accessory: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbolName: String
    let accessory: Accessory

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        symbolName: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.20), Color(red: 0.56, green: 0.45, blue: 1.0).opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                accessory
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [Color.white.opacity(0.38), Color.accentColor.opacity(0.055)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.46), lineWidth: 1)
        }
        .shadow(color: Color.accentColor.opacity(0.08), radius: 22, x: 0, y: 14)
    }
}

struct ControlPanelHeader: View {
    let title: String
    let subtitle: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GuidanceCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        }
    }
}

struct SourceNoticeCard: View {
    let level: SourceNoticeLevel
    let title: String
    let message: String
    let hasDiagnostic: Bool
    let primaryActionTitle: String?
    let showsDismissButton: Bool
    let primaryAction: () -> Void
    let copyAction: () -> Void
    let revealAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(accentColor)
                .frame(width: 30, height: 30)
                .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let primaryActionTitle {
                        Button(primaryActionTitle, action: primaryAction)
                            .buttonStyle(GlassButtonStyle(.primary))
                            .controlSize(.small)
                    }
                    Button("复制诊断", action: copyAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                        .disabled(!hasDiagnostic)
                    Button("显示支持文件夹", action: revealAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    if showsDismissButton {
                        Button("关闭提示", action: dismissAction)
                            .buttonStyle(GlassButtonStyle(.subtle))
                            .controlSize(.small)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentColor.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accentColor.opacity(0.20), lineWidth: 1)
        }
    }

    private var iconName: String {
        switch level {
        case .automaticFallback:
            return "arrow.trianglehead.branch"
        case .warning, .failure:
            return "exclamationmark.bubble"
        }
    }

    private var accentColor: Color {
        switch level {
        case .automaticFallback:
            return .accentColor
        case .warning, .failure:
            return .orange
        }
    }
}

struct DownloadRecoveryCard: View {
    let message: String
    let hasDiagnostic: Bool
    let copyAction: () -> Void
    let revealAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.trianglehead.clockwise")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("已恢复上次中断的下载会话")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("复制诊断", action: copyAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                        .disabled(!hasDiagnostic)
                    Button("显示支持文件夹", action: revealAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
    }
}

struct DownloadNoticeCard: View {
    let message: String
    let primaryActionTitle: String
    let hasDiagnostic: Bool
    let primaryAction: () -> Void
    let copyAction: () -> Void
    let revealAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.headline)
                .foregroundStyle(Color.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("下载操作需要处理")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(GlassButtonStyle(.primary))
                        .controlSize(.small)
                    Button("复制诊断", action: copyAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                        .disabled(!hasDiagnostic)
                    Button("显示支持文件夹", action: revealAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("关闭提示", action: dismissAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        }
    }
}

struct DownloadIntegrityNoticeCard: View {
    let message: String
    let primaryActionTitle: String?
    let hasDiagnostic: Bool
    let primaryAction: (() -> Void)?
    let copyAction: () -> Void
    let revealAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(Color.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("已下载文件需要处理")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let primaryActionTitle, let primaryAction {
                        Button(primaryActionTitle, action: primaryAction)
                            .buttonStyle(GlassButtonStyle(.primary))
                            .controlSize(.small)
                    }
                    Button("复制诊断", action: copyAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                        .disabled(!hasDiagnostic)
                    Button("显示文件夹", action: revealAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("关闭提示", action: dismissAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        }
    }
}

struct SettingsNoticeCard: View {
    let message: String
    let copyAction: () -> Void
    let revealAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gearshape.2")
                .font(.headline)
                .foregroundStyle(Color.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("设置未能保存")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("复制诊断", action: copyAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("显示支持文件夹", action: revealAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("关闭提示", action: dismissAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        }
    }
}

struct FavoriteNoticeCard: View {
    let message: String
    let primaryActionTitle: String
    let copyAction: () -> Void
    let revealAction: () -> Void
    let dismissAction: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "star.circle")
                .font(.headline)
                .foregroundStyle(Color.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("收藏操作需要处理")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(GlassButtonStyle(.primary))
                        .controlSize(.small)
                    Button("复制诊断", action: copyAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("显示支持文件夹", action: revealAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("关闭提示", action: dismissAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        }
    }
}

struct SaveDirectoryNoticeCard: View {
    let message: String
    let primaryActionTitle: String
    let copyAction: () -> Void
    let revealAction: () -> Void
    let dismissAction: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.headline)
                .foregroundStyle(Color.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("保存目录需要处理")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(GlassButtonStyle(.primary))
                        .controlSize(.small)
                    Button("复制诊断", action: copyAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("显示支持文件夹", action: revealAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("关闭提示", action: dismissAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        }
    }
}

struct SupportDirectoryNoticeCard: View {
    let message: String
    let retryAction: () -> Void
    let copyAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(Color.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("支持文件夹无法显示")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("重试打开", action: retryAction)
                        .buttonStyle(GlassButtonStyle(.primary))
                        .controlSize(.small)
                    Button("复制诊断", action: copyAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("关闭提示", action: dismissAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        }
    }
}

struct UpdateNoticeCard: View {
    let message: String
    let primaryActionTitle: String
    let hasDiagnostic: Bool
    let primaryAction: () -> Void
    let copyAction: () -> Void
    let revealActionTitle: String
    let revealAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down.app")
                .font(.headline)
                .foregroundStyle(Color.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("更新操作需要处理")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(GlassButtonStyle(.primary))
                        .controlSize(.small)
                    Button("复制诊断", action: copyAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                        .disabled(!hasDiagnostic)
                    Button(revealActionTitle, action: revealAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                    Button("关闭提示", action: dismissAction)
                        .buttonStyle(GlassButtonStyle(.subtle))
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        }
    }
}

struct ResultPanelToolbar<Accessory: View>: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let accessory: Accessory

    init(title: String, subtitle: String, symbolName: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            accessory
        }
        .padding(.vertical, 8)
    }
}

struct FieldBlock<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}
