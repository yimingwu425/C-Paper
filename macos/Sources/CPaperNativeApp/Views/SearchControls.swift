import SwiftUI

struct SubjectPicker: View {
    let subjects: [Subject]
    @Binding var selection: Subject?
    @Binding var manualCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassMenuField(selection: $selection, systemImage: "books.vertical") {
                Text(subjects.isEmpty ? "科目列表不可用" : "选择科目")
                    .tag(Optional<Subject>.none)
                ForEach(subjects) { subject in
                    Text(subject.displayName).tag(Optional(subject))
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selection?.displayName ?? (subjects.isEmpty ? "科目列表不可用" : "选择科目"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(selection == nil ? .secondary : .primary)
                        .lineLimit(1)
                    if subjects.isEmpty {
                        Text("可在下方输入 4 位科目代码")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .onChange(of: selection) { _, newValue in
                if newValue != nil {
                    manualCode = ""
                }
            }

            GlassTextField("手动输入科目代码，如 9709", text: manualBinding, systemImage: "number")
                .onChange(of: manualCode) { _, newValue in
                    if SubjectNormalizer.subjectCode(in: newValue) != nil {
                        selection = nil
                    }
                }
        }
    }

    private var manualBinding: Binding<String> {
        Binding(
            get: { manualCode },
            set: { value in
                manualCode = String(value.filter(\.isNumber).prefix(4))
            }
        )
    }
}

struct CompactYearField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Year", text: textBinding)
            .textFieldStyle(.plain)
            .font(.callout.monospacedDigit())
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 58)
            .background {
                RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                    .stroke(isFocused ? Color.accentColor.opacity(0.42) : Color.secondary.opacity(0.16), lineWidth: 1)
            }
            .focused($isFocused)
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { String(value) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                guard let parsed = Int(digits) else { return }
                value = min(max(parsed, range.lowerBound), range.upperBound)
            }
        )
    }
}

struct SeasonPillPicker: View {
    @Binding var selection: Season

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Season.allCases) { season in
                Button {
                    selection = season
                } label: {
                    Text(season.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(selection == season ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                                .fill(Color.primary.opacity(selection == season ? 0.070 : 0.025))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                                .stroke(selection == season ? Color.accentColor.opacity(0.26) : Color.secondary.opacity(0.14), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
