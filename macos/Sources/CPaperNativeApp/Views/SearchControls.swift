import SwiftUI

struct SubjectPicker: View {
    let subjects: [Subject]
    @Binding var selection: Subject?
    @Binding var manualCode: String
    let inspection = Inspection<Self>()
    @State private var isPopoverPresented = false
    @State private var searchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                searchQuery = ""
                isPopoverPresented = true
            } label: {
                GlassInputShell(systemImage: "books.vertical") {
                    HStack(spacing: 8) {
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
                            } else if selection == nil {
                                Text("支持按代码或名称搜索")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 6)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(subjects.isEmpty)
            .inspectablePopover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                SubjectPickerPopover(
                    subjects: subjects,
                    selection: $selection,
                    searchQuery: $searchQuery,
                    isPresented: $isPopoverPresented
                )
                .frame(width: 320, height: 340)
            }
            .onChange(of: selection) { _, newValue in
                let nextState = SubjectPickerLogic.subjectSelectionState(
                    for: newValue,
                    manualCode: manualCode
                )
                manualCode = nextState.manualCode
            }
            .onChange(of: isPopoverPresented) { _, isPresented in
                if !isPresented {
                    searchQuery = ""
                }
            }

            GlassTextField("手动输入科目代码，如 9709", text: manualBinding, systemImage: "number")
                .onChange(of: manualCode) { _, newValue in
                    let nextState = SubjectPickerLogic.manualCodeState(
                        for: newValue,
                        selection: selection
                    )
                    selection = nextState.selection
                }
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
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

private struct SubjectPickerPopover: View {
    let subjects: [Subject]
    @Binding var selection: Subject?
    @Binding var searchQuery: String
    @Binding var isPresented: Bool
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassInputShell(systemImage: "magnifyingglass", isFocused: isSearchFocused) {
                TextField("搜索科目代码或名称", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    SubjectPickerRow(
                        title: "不选择科目",
                        subtitle: "改用下方 4 位代码搜索",
                        isSelected: selection == nil
                    ) {
                        selection = nil
                        isPresented = false
                    }

                    if filteredSubjects.isEmpty {
                        Text("没有匹配的科目")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(filteredSubjects) { subject in
                            SubjectPickerRow(
                                title: subject.displayName,
                                subtitle: "科目代码 \(subject.code)",
                                isSelected: selection == subject
                            ) {
                                selection = subject
                                isPresented = false
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(14)
        .background(.regularMaterial)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var filteredSubjects: [Subject] {
        SubjectPickerLogic.filteredSubjects(subjects, query: searchQuery)
    }
}

private struct SubjectPickerRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.075 : 0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor.opacity(0.26) : Color.secondary.opacity(0.14),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
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
