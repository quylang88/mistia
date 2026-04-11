import SwiftUI

/// Shared spacing constants for consistent card description styling across the app
struct MistiaSpacing {
    /// Distance between card and description text above it (negative = pull description up)
    static let cardToDescriptionTop: CGFloat = -4
    /// Distance between description text and next card below it
    static let descriptionToCardBottom: CGFloat = 8
}

extension View {
    /// Apply standard spacing for card description text (pulls up to card above, adds space below)
    func cardDescriptionStyle() -> some View {
        self
            .offset(y: MistiaSpacing.cardToDescriptionTop)
            .padding(.bottom, MistiaSpacing.descriptionToCardBottom)
    }
}
