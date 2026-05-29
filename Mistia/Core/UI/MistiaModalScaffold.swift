import SwiftUI

struct MistiaModalScaffold<Title: View, Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let titleView: Title
    let accent: Color
    let onSave: () -> Void
    let content: Content

    private var groupedBackground: Color {
        Color(UIColor.systemGroupedBackground)
    }

    private var checkmarkForeground: Color {
        MistiaAccent.checkmarkPurple.color
    }

    init(
        @ViewBuilder titleView: () -> Title,
        accent: Color,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.titleView = titleView()
        self.accent = accent
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                groupedBackground
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        content
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    titleView
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(checkmarkForeground)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(accent)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(groupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(groupedBackground)
    }
}

extension MistiaModalScaffold where Title == Text {
    init(
        title: String,
        accent: Color,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            titleView: {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            },
            accent: accent,
            onSave: onSave,
            content: content
        )
    }
}
