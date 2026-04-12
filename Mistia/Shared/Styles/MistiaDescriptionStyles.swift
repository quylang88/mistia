import SwiftUI

/// Shared styling and spacing constants for card descriptions and related UI elements
struct MistiaCardStyles {
    // MARK: - Description Text Styling
    struct Description {
        static let fontSize: CGFloat = 13
        static let fontWeight: Font.Weight = .medium
        static let horizontalPadding: CGFloat = 4
    }
    
    // MARK: - Spacing Constants
    /// Distance between card and description text above it (negative = pull description up)
    static let cardToDescriptionTop: CGFloat = -4
    /// Distance between description text and next card below it
    static let descriptionToCardBottom: CGFloat = 8
}

extension View {
    /// Apply standard description text styling (font, color, padding)
    func descriptionTextStyle() -> some View {
        self
            .font(.system(size: MistiaCardStyles.Description.fontSize, weight: MistiaCardStyles.Description.fontWeight, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, MistiaCardStyles.Description.horizontalPadding)
    }
    
    /// Apply standard spacing for card description text (pulls up to card above, adds space below)
    /// Use with descriptionTextStyle() for complete description styling
    func cardDescriptionStyle() -> some View {
        self
            .offset(y: MistiaCardStyles.cardToDescriptionTop)
            .padding(.bottom, MistiaCardStyles.descriptionToCardBottom)
    }
}
