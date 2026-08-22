import SwiftUI

public struct FeedbackPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRating: Int? = nil
    @State private var showFullFeedbackSheet: Bool = false

    @State private var hasResponded: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Text(verbatim: "💬")
                .font(.system(size: 44))

            VStack(spacing: 6) {
                Text(L10n.settings.feedback.prompt.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(L10n.settings.feedback.prompt.message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            HStack(spacing: 14) {
                EmojiRatingButton(emoji: "😡", rating: 1, selectedRating: $selectedRating, action: handleRating)
                EmojiRatingButton(emoji: "🙁", rating: 2, selectedRating: $selectedRating, action: handleRating)
                EmojiRatingButton(emoji: "😐", rating: 3, selectedRating: $selectedRating, action: handleRating)
                EmojiRatingButton(emoji: "😊", rating: 4, selectedRating: $selectedRating, action: handleRating)
                EmojiRatingButton(emoji: "😍", rating: 5, selectedRating: $selectedRating, action: handleRating)
            }
            .padding(.vertical, 8)

            HStack {
                Button(L10n.settings.feedback.prompt.later) {
                    hasResponded = true
                    FeedbackPromptCoordinator.shared.recordPromptResponded(optOut: false)
                    dismiss()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

                Spacer()

                Button(L10n.settings.feedback.prompt.optOut) {
                    hasResponded = true
                    FeedbackPromptCoordinator.shared.recordPromptResponded(optOut: true)
                    dismiss()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.red)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .presentationDetents([.height(310)])
        .presentationCornerRadius(24)
        .onDisappear {
            if !hasResponded {
                FeedbackPromptCoordinator.shared.recordPromptResponded(optOut: false)
            }
        }
        .sheet(isPresented: $showFullFeedbackSheet, onDismiss: {
            dismiss()
        }) {
            SendFeedbackView(initialCategory: (selectedRating ?? 3) <= 2 ? .bug : .general)
        }
    }

    private func handleRating(_ rating: Int) {
        hasResponded = true
        FeedbackPromptCoordinator.shared.recordPromptResponded(optOut: rating >= 4)
        if rating <= 3 {
            showFullFeedbackSheet = true
        } else {
            dismiss()
        }
    }
}

private struct EmojiRatingButton: View {
    let emoji: String
    let rating: Int
    @Binding var selectedRating: Int?
    let action: (Int) -> Void

    var body: some View {
        Button(action: {
            selectedRating = rating
            action(rating)
        }) {
            Text(verbatim: emoji)
                .font(.system(size: 32))
                .padding(10)
                .background(selectedRating == rating ? MistiaAccent.purple.color.opacity(0.2) : Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(Circle())
        }
        .accessibilityLabel(L10n.settings.feedback.prompt.ratingAccessibility(rating))
    }
}
