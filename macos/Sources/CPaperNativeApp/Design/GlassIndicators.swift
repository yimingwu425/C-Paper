import SwiftUI

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
