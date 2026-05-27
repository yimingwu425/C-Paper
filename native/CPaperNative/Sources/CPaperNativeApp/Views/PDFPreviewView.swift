import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    let model: AppModel
    let file: PaperFile?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var localURL: URL? = nil
    @State private var isDownloading = false
    @State private var loadingError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.md) {
            if let file {
                GlassSurface(role: .floating, padding: CPDesign.Spacing.md) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.filename)
                                .font(.headline)
                                .lineLimit(1)
                            Text(file.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            if let localURL {
                                Button {
                                    model.bridge.open_folder(path: localURL.deletingLastPathComponent().path)
                                } label: {
                                    Label("定位", systemImage: "folder")
                                }
                                .buttonStyle(GlassButtonStyle(.normal))
                            }

                            Link(destination: file.url) {
                                Label("浏览器打开", systemImage: "safari")
                            }
                            .buttonStyle(GlassButtonStyle(.normal))

                            Button {
                                Task {
                                    await downloadSingleFile(file)
                                }
                            } label: {
                                Label("下载", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(GlassButtonStyle(.primary))
                        }
                    }
                }
                .padding([.horizontal, .top], CPDesign.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))

                ZStack {
                    if isDownloading {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("正在缓存试卷预览...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let localURL {
                        PDFKitContainer(url: localURL)
                    } else if let loadingError {
                        ContentUnavailableView(
                            "无法加载预览",
                            systemImage: "exclamationmark.triangle",
                            description: Text(loadingError + "\n您也可以直接点击右上角「下载」或「浏览器打开」。")
                        )
                    }
                }
                .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
                .padding(.horizontal, CPDesign.Spacing.md)
                .padding(.bottom, CPDesign.Spacing.md)
            } else {
                ContentUnavailableView(
                    "PDF 预览",
                    systemImage: "doc.richtext",
                    description: Text("选择一份试卷后在这里预览。")
                )
            }
        }
        .nativeContentBackground()
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: file)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: isDownloading)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: localURL)
        .task(id: file) {
            guard let file else { return }
            await loadPDF(for: file)
        }
    }

    private func loadPDF(for file: PaperFile) async {
        isDownloading = true
        loadingError = nil
        localURL = nil

        // 1. 优先检测是否已经下载过本地文件
        if let localPath = checkLocalDownloadedFile(file: file) {
            self.localURL = localPath
            isDownloading = false
            return
        }

        // 2. 否则，异步缓存网络 PDF
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let destinationURL = tempDir.appendingPathComponent(file.filename)

            // 如果临时文件夹已经有该缓存了，则直接载入
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                self.localURL = destinationURL
                isDownloading = false
                return
            }

            let (tempURL, response) = try await URLSession.shared.download(from: file.url)

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw NSError(domain: "PDFDownload", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "服务器错误: HTTP \(httpResponse.statusCode)"])
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            self.localURL = destinationURL
        } catch {
            self.loadingError = error.localizedDescription
        }
        isDownloading = false
    }

    private func checkLocalDownloadedFile(file: PaperFile) -> URL? {
        let expandedPath = (model.settings.saveDirectory as NSString).expandingTildeInPath

        // 场景 A: 合并文件夹
        let pathMerge = URL(fileURLWithPath: expandedPath).appendingPathComponent(file.filename)
        if FileManager.default.fileExists(atPath: pathMerge.path) {
            return pathMerge
        }

        // 场景 B: 年份与子文件夹
        if let year = file.year.map(String.init), let type = file.paperType?.uppercased() {
            let subfolder = (type == "QP" || type == "MS") ? type : ""
            let pathSplit = URL(fileURLWithPath: expandedPath)
                .appendingPathComponent(year)
                .appendingPathComponent(subfolder)
                .appendingPathComponent(file.filename)
            if FileManager.default.fileExists(atPath: pathSplit.path) {
                return pathSplit
            }
        }

        return nil
    }

    private func downloadSingleFile(_ file: PaperFile) async {
        do {
            let chosenDirectory = try await model.bridge.send(method: "choose_directory", params: EmptyParams(), payloadType: String.self)
            guard !chosenDirectory.isEmpty else {
                return
            }
            model.settings.saveDirectory = chosenDirectory

            let group = createBackendGroup(from: file)
            let params = DownloadStartParams(
                groups: [group],
                saveDir: model.settings.saveDirectory,
                options: model.settings.downloadOptions
            )

            let result = try await model.bridge.send(method: "start_download", params: params, payloadType: DownloadStartResult.self)
            guard result.ok else {
                throw PythonBridgeError.backend("下载任务启动失败")
            }

            model.route = .downloads
            await model.refreshDownloads()
            model.startPollingDownloads()

            // 关闭 sheet
            model.selectedPreview = nil
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func createBackendGroup(from file: PaperFile) -> BackendPaperGroup {
        let syCode = getSyCode(season: file.season, year: file.year)
        let type = file.paperType?.uppercased()

        if type == "QP" {
            return BackendPaperGroup(
                subject: file.subjectCode,
                sy: syCode,
                number: file.number,
                paperGroup: nil,
                qp: file.filename,
                ms: nil,
                filename: nil,
                ftype: nil,
                label: file.label
            )
        } else if type == "MS" {
            return BackendPaperGroup(
                subject: file.subjectCode,
                sy: syCode,
                number: file.number,
                paperGroup: nil,
                qp: nil,
                ms: file.filename,
                filename: nil,
                ftype: nil,
                label: file.label
            )
        } else {
            return BackendPaperGroup(
                subject: file.subjectCode,
                sy: syCode,
                number: file.number,
                paperGroup: nil,
                qp: nil,
                ms: nil,
                filename: file.filename,
                ftype: file.paperType?.lowercased(),
                label: file.label
            )
        }
    }

    private func getSyCode(season: String?, year: Int?) -> String? {
        guard let season, let year else { return nil }
        let prefix: String
        switch season {
        case "Mar": prefix = "m"
        case "Jun": prefix = "s"
        case "Nov": prefix = "w"
        default: prefix = "w"
        }
        let yearShort = String(year % 100)
        let yearStr = yearShort.count == 1 ? "0\(yearShort)" : yearShort
        return "\(prefix)\(yearStr)"
    }
}

struct PDFKitContainer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}
