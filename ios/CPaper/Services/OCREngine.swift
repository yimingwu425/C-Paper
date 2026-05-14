import Foundation
import Vision
import PDFKit
import UIKit

@Observable
final class OCREngine {
    var isProcessing = false
    var progress: Double = 0
    var error: String?

    func extractText(from pdfURL: URL) async throws -> OCRResult {
        isProcessing = true
        progress = 0
        defer { isProcessing = false }

        guard let document = PDFDocument(url: pdfURL) else {
            throw APIError.validationError("无法打开 PDF 文件")
        }

        let pageCount = document.pageCount
        var pages: [String] = []
        var questions: [OCRQuestion] = []

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 3.0 // 300 DPI equivalent
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

            UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                continue
            }
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
                UIGraphicsEndImageContext()
                continue
            }
            UIGraphicsEndImageContext()

            let pageText = try await recognizeText(from: image)
            pages.append(pageText)

            let pageQuestions = splitQuestions(pageText, page: i + 1)
            questions.append(contentsOf: pageQuestions)

            progress = Double(i + 1) / Double(pageCount)
        }

        return OCRResult(
            fullText: pages.joined(separator: "\n\n"),
            pages: pages,
            questions: questions,
            metadata: ["page_count": pageCount]
        )
    }

    private func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func splitQuestions(_ text: String, page: Int) -> [OCRQuestion] {
        var questions: [OCRQuestion] = []
        let pattern = /(?:Question\s+|Q)?(\d+(?:\s*\([a-z]\))?)\s*[\.\[:]/

        let lines = text.components(separatedBy: .newlines)
        var currentNum: String?
        var currentText = ""

        for line in lines {
            if let match = line.firstMatch(of: pattern) {
                if let num = currentNum, !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
                    questions.append(OCRQuestion(number: num, text: currentText.trimmingCharacters(in: .whitespaces), page: page))
                }
                currentNum = String(match.1)
                currentText = ""
            } else {
                currentText += line + "\n"
            }
        }

        if let num = currentNum, !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
            questions.append(OCRQuestion(number: num, text: currentText.trimmingCharacters(in: .whitespaces), page: page))
        }

        return questions
    }
}

struct OCRResult {
    let fullText: String
    let pages: [String]
    let questions: [OCRQuestion]
    let metadata: [String: Int]
}

struct OCRQuestion {
    let number: String
    let text: String
    let page: Int
}
