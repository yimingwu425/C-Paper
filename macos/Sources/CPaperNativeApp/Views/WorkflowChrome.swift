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
