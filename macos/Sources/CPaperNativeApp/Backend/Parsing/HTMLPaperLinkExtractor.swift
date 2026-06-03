import Foundation
import SwiftSoup

struct HTMLPaperLinkExtractor {
    func extractPDFLinks(
        from html: String,
        baseURL: URL,
        sourceID: PaperSourceID
    ) throws -> [PaperComponent] {
        let document = try SwiftSoup.parse(html, baseURL.absoluteString)
        let anchors = try document.select("a[href]")
        var seen: Set<String> = []
        var components: [PaperComponent] = []

        for anchor in anchors.array() {
            let href = try anchor.attr("href")
            guard
                let absoluteURL = resolvedURL(href: href, baseURL: baseURL),
                absoluteURL.path.lowercased().hasSuffix(".pdf")
            else {
                continue
            }

            let filename = absoluteURL.lastPathComponent.removingPercentEncoding ?? absoluteURL.lastPathComponent
            guard
                let parsed = PaperFilenameParser.parse(filename),
                !seen.contains(absoluteURL.absoluteString)
            else {
                continue
            }

            seen.insert(absoluteURL.absoluteString)
            components.append(.sourceComponent(sourceID: sourceID, parsed: parsed, url: absoluteURL))
        }

        return components.sorted { lhs, rhs in
            lhs.filename < rhs.filename
        }
    }

    private func resolvedURL(href: String, baseURL: URL) -> URL? {
        let cleaned = href
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: cleaned, relativeTo: baseURL)?.absoluteURL
    }
}
