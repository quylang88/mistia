import SwiftUI

struct MistiaModalScaffold<Title: View, Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let titleView: Title
    let accent: Color
    let onSave: () -> Void
    let content: Content

    private var modalBackground: Color {
        Color(UIColor.systemGroupedBackground)
    }

    private var toolbarConfirmTint: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var toolbarConfirmForeground: Color {
        Color(red: 0.88, green: 0.78, blue: 1.0)
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
                modalBackground
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        content
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
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
                            .foregroundStyle(toolbarConfirmForeground)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(toolbarConfirmTint)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
        }
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
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            },
            accent: accent,
            onSave: onSave,
            content: content
        )
    }
}
