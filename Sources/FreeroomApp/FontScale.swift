import SwiftUI

/// App-wide text size (Small / Medium / Large). macOS has no Dynamic Type, so Freeroom scales its
/// own fonts: every text style goes through `Font.fr(_:)`. Root views are re-created on change.
enum FontScale {
    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var factor: CGFloat {
            switch self {
            case .small: 0.9
            case .medium: 1.0
            case .large: 1.2
            }
        }
    }

    nonisolated(unsafe) static var factor: CGFloat = 1.0

    /// macOS default point sizes per text style.
    static func base(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline: 13
        case .subheadline: 11
        case .body: 13
        case .callout: 12
        case .footnote: 10
        case .caption: 10
        case .caption2: 10
        @unknown default: 13
        }
    }

    static func size(_ points: CGFloat) -> CGFloat { (points * factor).rounded() }
}

extension Font {
    /// A text style scaled by the user's text size setting.
    static func fr(_ style: Font.TextStyle, design: Font.Design = .default) -> Font {
        .system(size: FontScale.size(FontScale.base(style)),
                weight: style == .headline ? .semibold : .regular,
                design: design)
    }
}
