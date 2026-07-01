import SwiftUI

enum SleepColor {
    static let bgTop = Color(red: 42 / 255, green: 28 / 255, blue: 102 / 255)
    static let bgMid = Color(red: 36 / 255, green: 24 / 255, blue: 88 / 255)
    static let bgBottom = Color(red: 23 / 255, green: 15 / 255, blue: 54 / 255)
    static let indigo = Color(red: 41 / 255, green: 25 / 255, blue: 101 / 255)
    static let purple = Color(red: 83 / 255, green: 62 / 255, blue: 168 / 255)
    static let magenta = Color(red: 148 / 255, green: 62 / 255, blue: 195 / 255)
    static let moon = Color(red: 244 / 255, green: 241 / 255, blue: 255 / 255)
    static let peach = Color(red: 233 / 255, green: 180 / 255, blue: 136 / 255)
    static let clay = Color(red: 217 / 255, green: 142 / 255, blue: 110 / 255)
    static let white = Color.white
    static let dim = Color.white.opacity(0.74)
    static let quiet = Color.white.opacity(0.52)
    static let faint = Color.white.opacity(0.30)
    static let hairline = Color.white.opacity(0.10)
    static let glassFill = Color.white.opacity(0.06)
}

enum SleepSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 40
}

enum SleepRadius {
    static let sm: CGFloat = 14
    static let md: CGFloat = 18
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
    static let pill: CGFloat = 999
}

enum SleepFont {
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

