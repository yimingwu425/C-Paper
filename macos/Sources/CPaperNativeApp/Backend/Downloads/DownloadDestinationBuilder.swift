import Foundation

struct DownloadDestinationTask: Codable, Hashable {
    var id: Int
    var component: PaperComponent
    var filename: String
    var ftype: String
    var label: String
    var year: String
    var saveURL: URL

    var displayItem: DownloadTaskItem {
        DownloadTaskItem(
            id: id,
            filename: filename,
            ftype: ftype,
            label: label,
            year: year,
            savePath: saveURL.path,
            status: .pending,
            error: "",
            errorType: nil
        )
    }
}

struct DownloadDestinationPlan {
    var tasks: [DownloadDestinationTask]
    var skipped: Int
}

enum DownloadDestinationError: LocalizedError, Equatable {
    case invalidSaveDirectory

    var errorDescription: String? {
        switch self {
        case .invalidSaveDirectory:
            "保存目录无效。"
        }
    }
}

enum DownloadDestinationBuilder {
    static func build(
        groups: [NativePaperGroup],
        saveDirectory: URL,
        options: DownloadOptions,
        downloadedFilenames: Set<String> = [],
        fileManager: FileManager = .default
    ) throws -> DownloadDestinationPlan {
        guard saveDirectory.isFileURL else {
            throw DownloadDestinationError.invalidSaveDirectory
        }

        let root = saveDirectory.standardizedFileURL
        var tasks: [DownloadDestinationTask] = []
        var skipped = 0

        for group in groups {
            let components = [group.qp, group.ms].compactMap { $0 } + group.extras
            let groupYear = yearString(from: group.sy)

            for component in components {
                let year = safeFolderComponent(component.year.map(String.init) ?? groupYear)
                guard !year.isEmpty else { continue }

                let ftype = component.paperType.uppercased()
                guard ftype == "QP" || ftype == "MS" else { continue }
                if ftype == "MS" && !options.includeMarkSchemes {
                    continue
                }

                guard let filename = safePDFFileName(component.filename, url: component.url) else {
                    continue
                }

                let directory = options.merge
                    ? root
                    : root.appendingPathComponent(year, isDirectory: true)
                        .appendingPathComponent(ftype, isDirectory: true)
                let saveURL = directory.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
                guard isContained(saveURL, in: root) else { continue }

                let exists = fileManager.fileExists(atPath: saveURL.path)
                switch options.duplicateMode {
                case .overwrite:
                    break
                case .skip:
                    if downloadedFilenames.contains(filename) {
                        skipped += 1
                        continue
                    }
                case .missing:
                    if downloadedFilenames.contains(filename) && exists {
                        skipped += 1
                        continue
                    }
                }

                tasks.append(
                    DownloadDestinationTask(
                        id: tasks.count,
                        component: component,
                        filename: filename,
                        ftype: ftype,
                        label: component.label ?? groupLabel(group),
                        year: year,
                        saveURL: saveURL
                    )
                )
            }
        }

        return DownloadDestinationPlan(tasks: tasks, skipped: skipped)
    }

    static func existingDownloadURL(
        for file: PaperFile,
        saveDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let root = saveDirectory.standardizedFileURL
        let filename = file.filename
        guard filename == (filename as NSString).lastPathComponent else { return nil }

        let mergedURL = root.appendingPathComponent(filename, isDirectory: false)
        if fileManager.fileExists(atPath: mergedURL.path) {
            return mergedURL
        }

        guard let year = file.year.map(String.init) else { return nil }
        let paperType = file.paperType?.uppercased() ?? ""
        guard paperType == "QP" || paperType == "MS" else { return nil }

        let splitURL = root
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(paperType, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
        if fileManager.fileExists(atPath: splitURL.path) {
            return splitURL
        }

        return nil
    }

    static func safePDFFileName(_ value: String, url: URL) -> String? {
        guard !value.isEmpty else { return nil }
        let lower = value.lowercased()
        guard lower.hasSuffix(".pdf") else { return nil }
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        guard value == (value as NSString).lastPathComponent else { return nil }
        guard !value.hasPrefix(".") else { return nil }
        guard !value.contains("..") else { return nil }

        let forbidden = CharacterSet(charactersIn: "/\\<>:|?*\"")
        guard value.rangeOfCharacter(from: forbidden) == nil else { return nil }
        return value
    }

    private static func safeFolderComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private static func isContained(_ child: URL, in parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    private static func yearString(from sy: String?) -> String {
        guard let year = PaperFilenameParser.year(fromSY: sy) else { return "" }
        return String(year)
    }

    private static func groupLabel(_ group: NativePaperGroup) -> String {
        if let number = group.number, !number.isEmpty {
            return "Paper \(number)"
        }
        return group.subjectCode ?? ""
    }
}
