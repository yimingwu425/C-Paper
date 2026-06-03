import Foundation

enum PaperGrouper {
    static func groups(from components: [PaperComponent]) -> [NativePaperGroup] {
        var pairs: [String: NativePaperGroupBuilder] = [:]
        var standalone: [PaperComponent] = []

        for component in components {
            let type = component.paperType.lowercased()
            guard type == "qp" || type == "ms",
                  let subject = component.subjectCode,
                  let sy = component.sy
            else {
                standalone.append(component)
                continue
            }

            let key = [component.sourceID.rawValue, subject, sy, component.number ?? ""].joined(separator: "|")
            var builder = pairs[key] ?? NativePaperGroupBuilder(
                sourceID: component.sourceID,
                subjectCode: subject,
                sy: sy,
                number: component.number,
                paperGroup: PaperFilenameParser.paperGroup(of: component.number)
            )

            if type == "qp" {
                builder.qp = component
            } else {
                builder.ms = component
            }
            pairs[key] = builder
        }

        var groups = pairs.values.map(\.group)
        groups.sort {
            let lhsNumber = Int($0.number ?? "") ?? 999
            let rhsNumber = Int($1.number ?? "") ?? 999
            return (($0.paperGroup ?? 0), lhsNumber) < (($1.paperGroup ?? 0), rhsNumber)
        }

        groups.append(contentsOf: standalone.map { component in
            NativePaperGroup(
                sourceID: component.sourceID,
                subjectCode: component.subjectCode,
                sy: component.sy,
                number: component.number,
                paperGroup: 0,
                qp: nil,
                ms: nil,
                extras: [component]
            )
        })

        return groups
    }
}

private struct NativePaperGroupBuilder {
    let sourceID: PaperSourceID
    let subjectCode: String?
    let sy: String?
    let number: String?
    let paperGroup: Int?
    var qp: PaperComponent?
    var ms: PaperComponent?

    var group: NativePaperGroup {
        NativePaperGroup(
            sourceID: sourceID,
            subjectCode: subjectCode,
            sy: sy,
            number: number,
            paperGroup: paperGroup,
            qp: qp,
            ms: ms,
            extras: []
        )
    }
}
