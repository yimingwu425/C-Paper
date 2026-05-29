import SwiftUI

enum CPDesign {
    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 8
        static let panel: CGFloat = 14
        static let floating: CGFloat = 18
    }

    enum Motion {
        static let standard = Animation.spring(response: 0.32, dampingFraction: 0.88)
        static let tactile = Animation.spring(response: 0.24, dampingFraction: 0.82)
        static let gentle = Animation.easeInOut(duration: 0.18)

        static func standard(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : standard
        }

        static func tactile(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : tactile
        }

        static func gentle(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : gentle
        }
    }

    enum SurfaceRole: Equatable {
        case base
        case content
        case control
        case floating
        case modal

        var material: Material {
            switch self {
            case .base:
                return .bar
            case .content:
                return .regularMaterial
            case .control:
                return .thinMaterial
            case .floating:
                return .ultraThinMaterial
            case .modal:
                return .regularMaterial
            }
        }

        var radius: CGFloat {
            switch self {
            case .control:
                return CPDesign.Radius.control
            case .floating, .modal:
                return CPDesign.Radius.floating
            case .base, .content:
                return CPDesign.Radius.panel
            }
        }

        var shadowOpacity: Double {
            switch self {
            case .base:
                return 0.035
            case .content:
                return 0.06
            case .control:
                return 0.04
            case .floating:
                return 0.10
            case .modal:
                return 0.12
            }
        }
    }

    enum GlassButtonProminence {
        case subtle
        case normal
        case primary
        case destructive
    }
}
