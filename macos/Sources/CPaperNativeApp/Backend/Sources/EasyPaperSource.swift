import CommonCrypto
import Foundation

struct EasyPaperSource: PaperSource {
    let id: PaperSourceID = .easyPaper

    private let apiBaseURL: URL
    private let pdfBaseURL: URL
    private let networkClient: any NetworkClientProtocol
    private let requestBuilder: HTTPRequestBuilder
    private let crypto: EasyPaperCrypto

    init(
        apiBaseURL: URL = BackendConstants.easyPaperAPIBaseURL,
        pdfBaseURL: URL = BackendConstants.easyPaperPDFBaseURL,
        networkClient: any NetworkClientProtocol = NetworkClient(),
        requestBuilder: HTTPRequestBuilder = HTTPRequestBuilder(),
        crypto: EasyPaperCrypto = EasyPaperCrypto()
    ) {
        self.apiBaseURL = apiBaseURL
        self.pdfBaseURL = pdfBaseURL
        self.networkClient = networkClient
        self.requestBuilder = requestBuilder
        self.crypto = crypto
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        guard let year = query.year, let seasonDirectory = seasonDirectory(for: query) else {
            throw PaperSourceError.invalidResponse("EasyPaper 需要指定年份和季度")
        }

        let subjectDirectory = try await resolveSubjectDirectory(subjectCode: query.subjectCode)
        let targetDirectory = "\(subjectDirectory)|\(year)|\(seasonDirectory)"
        let listing = try await loadDirectory(targetDirectory)
        let components = try listing.files.compactMap { filename -> PaperComponent? in
            guard let parsed = PaperFilenameParser.parse(filename), parsed.subject == query.subjectCode else {
                return nil
            }
            let filePath = "\(targetDirectory)|\(filename)"
            let url = try fileURL(for: filePath)
            return .sourceComponent(sourceID: id, parsed: parsed, url: url)
        }
        .filter { $0.matches(query) }

        guard !components.isEmpty else {
            throw PaperSourceError.sourceUnavailable("EasyPaper 暂不可用：\(targetDirectory) 没有返回可下载试卷")
        }

        return SourceSearchResult(sourceID: id, components: components)
    }

    func healthCheck() async -> SourceHealth {
        do {
            _ = try await search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))
            return SourceHealth(sourceID: id, status: .available)
        } catch {
            return SourceHealth(sourceID: id, status: .unavailable, message: error.localizedDescription)
        }
    }

    private func resolveSubjectDirectory(subjectCode: String) async throws -> String {
        let roots = ["CAIE|AS and A Level", "CAIE|IGCSE", "CAIE|O Level", "CAIE|Pre-U"]
        for root in roots {
            let listing = try await loadDirectory(root)
            if let folder = listing.folders.first(where: { $0.contains("(\(subjectCode))") }) {
                return "\(root)|\(folder)"
            }
        }
        throw PaperSourceError.sourceUnavailable("EasyPaper 暂不可用：找不到科目 \(subjectCode) 的目录")
    }

    private func loadDirectory(_ directory: String) async throws -> EasyPaperDirectoryResponse {
        let token = try crypto.encryptedRequestToken(payload: [
            "dir": directory,
            "source": "website"
        ])
        let url = apiBaseURL
            .appendingPathComponent("paperdownload")
            .appendingPathComponent("dir_v3")
            .appendingPathComponent(token)
        let request = requestBuilder.get(url)
        let data = try await networkClient.data(for: request)
        let decrypted = try crypto.decryptResponse(data)
        guard decrypted.status else {
            throw PaperSourceError.sourceUnavailable("EasyPaper 暂不可用：目录 API 返回失败")
        }
        return decrypted
    }

    private func fileURL(for filePath: String) throws -> URL {
        let token = try crypto.encryptedRequestToken(payload: [
            "dir": filePath,
            "source": "website"
        ])
        let url = pdfBaseURL
            .appendingPathComponent("paperdownload")
            .appendingPathComponent("dir_v3")
            .appendingPathComponent(token)
        return url.withEasyPaperFilePath(filePath)
    }

    private func seasonDirectory(for query: PaperSourceQuery) -> String? {
        switch query.seasonPrefix {
        case "m": "March"
        case "s": "Summer"
        case "w": "Winter"
        default: nil
        }
    }
}

extension URL {
    func withEasyPaperFilePath(_ filePath: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.fragment = "easyPaperPath=\(Data(filePath.utf8).base64EncodedString())"
        return components.url ?? self
    }

    var easyPaperFilePath: String? {
        guard let fragment,
              fragment.hasPrefix("easyPaperPath="),
              let data = Data(base64Encoded: String(fragment.dropFirst("easyPaperPath=".count)))
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

struct EasyPaperDirectoryResponse: Decodable, Equatable {
    let status: Bool
    let folders: [String]
    let files: [String]
    let currentDirectory: String?
    let lockedResources: [String]

    enum CodingKeys: String, CodingKey {
        case status
        case folders
        case files
        case currentDirectory = "current_dir"
        case lockedResources = "locked_resources"
    }
}

struct EasyPaperCrypto: Sendable {
    private let requestKey = "hQgPeYGoPJAHatNyBejnINyJ7Ffb5fjVdasd2"
    private let requestIV = "8!cH-3SyWhZ9I&/1MwSZK3"
    private let responseKey = "w`:oI%@`N*=Aod~aVKR5`jO:zK&S#x~1ax2da"
    private let responseIV = "uf5h6Kall8g0o3GLE2UNJKko"
    private let replaceTarget = "%fo@~[C.4L1.ZDcp"
    private let randomString: @Sendable (Int) -> String
    private let now: @Sendable () -> Date

    init(
        randomString: @escaping @Sendable (Int) -> String = EasyPaperCrypto.defaultRandomString(length:),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.randomString = randomString
        self.now = now
    }

    func encryptedRequestToken(payload: [String: String]) throws -> String {
        var values = payload
        values["time"] = String(format: "%.0f", now().timeIntervalSince1970)
        let jsonData = try JSONSerialization.data(withJSONObject: values.sortedDictionary())
        let json = String(decoding: jsonData, as: UTF8.self)
        let plaintext = randomString(10) + json
        let encrypted = try crypt(
            Data(plaintext.utf8),
            key: String(requestKey.prefix(32)),
            iv: String(requestIV.prefix(16)),
            operation: CCOperation(kCCEncrypt)
        ).base64EncodedString()
        return encrypted
            .replacingOccurrences(of: "/", with: replaceTarget)
            .addingPercentEncoding(withAllowedCharacters: EasyPaperCrypto.componentAllowedCharacters) ?? encrypted
    }

    func decryptResponse(_ data: Data) throws -> EasyPaperDirectoryResponse {
        let encrypted = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: replaceTarget, with: "/")
        guard let encryptedData = Data(base64Encoded: encrypted) else {
            throw PaperSourceError.invalidResponse("EasyPaper returned invalid encrypted data")
        }
        let decryptedData = try crypt(
            encryptedData,
            key: String(responseKey.prefix(32)),
            iv: String(responseIV.prefix(16)),
            operation: CCOperation(kCCDecrypt)
        )
        let decrypted = String(decoding: decryptedData, as: UTF8.self)
        let json = String(decrypted.dropFirst(10))
        guard let jsonData = json.data(using: .utf8) else {
            throw PaperSourceError.invalidResponse("EasyPaper returned invalid JSON text")
        }
        return try JSONDecoder().decode(EasyPaperDirectoryResponse.self, from: jsonData)
    }

    private func crypt(_ data: Data, key: String, iv: String, operation: CCOperation) throws -> Data {
        let keyData = Data(key.utf8)
        let ivData = Data(iv.utf8)
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                keyData.withUnsafeBytes { keyBuffer in
                    ivData.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            kCCKeySizeAES256,
                            ivBuffer.baseAddress,
                            dataBuffer.baseAddress,
                            data.count,
                            outputBuffer.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw PaperSourceError.invalidResponse("EasyPaper AES operation failed: \(status)")
        }

        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static let componentAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    private static func defaultRandomString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHJKMNP9gqQRSToOLVvI1lWXYZabcdefhijkmnprstwxyz2345678")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}

private extension Dictionary where Key == String, Value == String {
    func sortedDictionary() -> [String: String] {
        Dictionary(uniqueKeysWithValues: sorted { $0.key < $1.key })
    }
}
