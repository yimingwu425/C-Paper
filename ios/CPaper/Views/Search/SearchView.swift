import SwiftUI

struct SearchView: View {
    @Environment(PaperService.self) private var paperService
    @State private var viewModel: SearchViewModel?
    @State private var showSubjectPicker = false

    var body: some View {
        Group {
            if let viewModel {
                @Bindable var vm = viewModel
                VStack(spacing: 0) {
                    // Search controls
                    GlassCard {
                        VStack(spacing: 12) {
                            Button {
                                showSubjectPicker = true
                            } label: {
                                HStack {
                                    Text(viewModel.selectedSubject?.name ?? "选择科目")
                                        .foregroundStyle(viewModel.selectedSubject != nil ? .primary : .secondary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 12) {
                                Picker("年份", selection: $vm.selectedYear) {
                                    ForEach((2015...2025).reversed(), id: \.self) { year in
                                        Text("\(year)").tag(year)
                                    }
                                }
                                .pickerStyle(.menu)

                                Picker("季节", selection: $vm.selectedSeason) {
                                    ForEach(Constants.seasons, id: \.self) { season in
                                        Text(season).tag(season)
                                    }
                                }
                                .pickerStyle(.menu)

                                Button("搜索") {
                                    Task { await viewModel.search() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(viewModel.selectedSubject == nil || viewModel.isLoading)
                            }
                        }
                    }
                    .padding()

                    // Results
                    if viewModel.isLoading {
                        ProgressView("搜索中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = viewModel.error {
                        ContentUnavailableView("搜索失败", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else if viewModel.results.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "搜索试卷", subtitle: "选择科目和年份开始搜索")
                    } else {
                        List(viewModel.results, id: \.filename) { paper in
                            PaperRowView(paper: paper)
                        }
                        .listStyle(.plain)
                    }
                }
                .navigationTitle("搜索")
                .sheet(isPresented: $showSubjectPicker) {
                    SubjectPickerView(subjects: viewModel.subjects, selected: $viewModel.selectedSubject)
                }
            } else {
                ProgressView()
                    .task {
                        let vm = SearchViewModel(paperService: paperService)
                        await vm.loadSubjects()
                        viewModel = vm
                    }
            }
        }
    }
}

struct PaperRowView: View {
    let paper: PaperSearchResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(paper.filename)
                    .font(.subheadline.weight(.medium))
                Text(PaperParser.parse(filename: paper.filename)?.paperType.displayName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}

struct SubjectPickerView: View {
    let subjects: [Subject]
    @Binding var selected: Subject?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filtered: [Subject] {
        searchText.isEmpty ? subjects : subjects.filter {
            $0.code.localizedCaseInsensitiveContains(searchText) ||
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { subject in
                Button {
                    selected = subject
                    dismiss()
                } label: {
                    HStack {
                        Text(subject.code).font(.subheadline.weight(.medium))
                        Text(subject.name).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        if selected?.id == subject.id {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .searchable(text: $searchText, prompt: "搜索科目")
            .navigationTitle("选择科目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
