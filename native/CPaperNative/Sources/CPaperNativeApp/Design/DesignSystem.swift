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
    }

    enum Motion {
        static let standard = Animation.spring(response: 0.32, dampingFraction: 0.86)
        static let gentle = Animation.easeInOut(duration: 0.18)
    }
}
