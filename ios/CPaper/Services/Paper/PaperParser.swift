import Foundation

enum PaperType: String {
    case qp, ms, ci, gt, er, ir, `in`, sr
    case unknown

    var displayName: String {
        switch self {
        case .qp: return "Question Paper"
        case .ms: return "Mark Scheme"
        case .ci: return "Confidential Instructions"
        case .gt: return "Grade Threshold"
        case .er: return "Examiner Report"
        case .ir: return "Insert"
        case .in: return "Instructions"
        case .sr: return "Specimen"
        case .unknown: return "Other"
        }
    }
}

struct ParsedPaper {
    let subject: String
    let seasonYear: String
    let paperType: PaperType
    let number: String
    let filename: String
}

enum PaperParser {
    static func parse(filename: String) -> ParsedPaper? {
        // Pattern: {subject}_{sy}_{type}_{number}.pdf
        // e.g. 9709_s23_qp_12.pdf
        let parts = filename.replacingOccurrences(of: ".pdf", with: "").components(separatedBy: "_")
        guard parts.count >= 3 else { return nil }

        let subject = parts[0]
        let seasonYear = parts[1]
        let typeStr = parts.count > 2 ? parts[2] : ""
        let number = parts.count > 3 ? parts[3] : ""

        let paperType = PaperType(rawValue: typeStr) ?? .unknown

        return ParsedPaper(
            subject: subject,
            seasonYear: seasonYear,
            paperType: paperType,
            number: number,
            filename: filename
        )
    }

    static func groupPapers(_ papers: [ParsedPaper]) -> [(qp: ParsedPaper?, ms: ParsedPaper?)] {
        var groups: [String: (qp: ParsedPaper?, ms: ParsedPaper?)] = [:]

        for paper in papers {
            let key = "\(paper.subject)_\(paper.seasonYear)_\(paper.number)"
            if paper.paperType == .qp {
                groups[key, default: (nil, nil)].qp = paper
            } else if paper.paperType == .ms {
                groups[key, default: (nil, nil)].ms = paper
            }
        }

        return Array(groups.values)
    }
}
