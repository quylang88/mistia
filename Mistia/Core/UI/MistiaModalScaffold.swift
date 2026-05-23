import SwiftUI

struct MistiaModalScaffold<Title: View, Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let titleView: Title
    let accent: Color
    let onSave: () -> Void
    let content: Content

    private var modalBackground: Color {
        Color(UIColor.systemGroupedBackground)
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
            ZStack(alignment: .top) {
                modalBackground
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
                    MistiaHeaderCircleButton(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    MistiaHeaderCircleButton(action: {
                        onSave()
                        dismiss()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(checkmarkForeground)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(accent)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(modalBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(modalBackground)
    }

    private var checkmarkForeground: Color {
        colorScheme == .dark ? accent : .white
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
