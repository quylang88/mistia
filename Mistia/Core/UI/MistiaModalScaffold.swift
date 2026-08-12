import SwiftUI

struct MistiaModalScaffold<Title: View, Content: View>: View {
    enum ContentStyle {
        /// Wraps content in a ScrollView + ZStack (default, for custom layouts)
        case scrollView
        /// Renders content directly — use when content is a SwiftUI Form
        case form
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let titleView: Title
    let accent: Color
    let contentStyle: ContentStyle
    let dismissGuardConfiguration: MistiaDismissGuardConfiguration?
    let saveDisabled: Bool
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
        contentStyle: ContentStyle = .scrollView,
        dismissGuardConfiguration: MistiaDismissGuardConfiguration? = nil,
        saveDisabled: Bool = false,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.titleView = titleView()
        self.accent = accent
        self.contentStyle = contentStyle
        self.dismissGuardConfiguration = dismissGuardConfiguration
        self.saveDisabled = saveDisabled
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        let modalContent = NavigationStack {
            Group {
                switch contentStyle {
                case .scrollView:
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
                case .form:
                    content
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    titleView
                }

                ToolbarItem(placement: .topBarLeading) {
                    if let dismissGuardConfiguration {
                        MistiaGuardedDismissButton(configuration: dismissGuardConfiguration)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
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
                    .disabled(saveDisabled)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(groupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(groupedBackground)

        if let dismissGuardConfiguration {
            modalContent.mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        } else {
            modalContent
        }
    }
}

extension MistiaModalScaffold where Title == Text {
    init(
        title: String,
        accent: Color,
        contentStyle: ContentStyle = .scrollView,
        dismissGuardConfiguration: MistiaDismissGuardConfiguration? = nil,
        saveDisabled: Bool = false,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            titleView: {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            },
            accent: accent,
            contentStyle: contentStyle,
            dismissGuardConfiguration: dismissGuardConfiguration,
            saveDisabled: saveDisabled,
            onSave: onSave,
            content: content
        )
    }
}
