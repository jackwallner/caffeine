import SwiftUI

enum Theme {
    // MARK: - Adaptive colors (light/dark)

    // watchOS has no UIKit semantic colors, so the palette forks rather than
    // failing to compile in the watch and complication targets.
    #if os(watchOS)
    static let background = Color.black
    static let cardSurface = Color(white: 0.12)
    static let cardSurfaceLight = Color(white: 0.18)
    static let ringTrack = Color(white: 0.2)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.7)
    static let textTertiary = Color(white: 0.5)
    #else
    static let background = Color(.systemBackground)
    static let cardSurface = Color(.secondarySystemBackground)
    static let cardSurfaceLight = Color(.tertiarySystemBackground)
    static let ringTrack = Color(.systemFill)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    #endif

    // Protein palette: warm amber through to a deep orange.
    static let protein = Color(red: 0.98, green: 0.55, blue: 0.13)
    static let proteinDeep = Color(red: 0.90, green: 0.29, blue: 0.13)
    static let proteinGlow = Color(red: 0.98, green: 0.55, blue: 0.13).opacity(0.3)

    static let positive = Color(red: 0.20, green: 0.72, blue: 0.48)
    static let negative = Color(red: 0.92, green: 0.36, blue: 0.38)
    static let coral = Color(red: 1.0, green: 0.45, blue: 0.40)

    // MARK: - Constants

    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 20

    // MARK: - Gradients

    static var proteinGradient: LinearGradient {
        LinearGradient(
            colors: [proteinDeep, protein],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Typography

    static func bigNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
