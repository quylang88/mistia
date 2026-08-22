import SwiftUI

struct OverviewWidgetManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var items: [OverviewSectionItemConfig]

    @State private var draftItems: [OverviewSectionItemConfig] = []
    @State private var initialItems: [OverviewSectionItemConfig] = []

    private var hasUnsavedChanges: Bool {
        draftItems != initialItems
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: .editing,
            hasUnsavedChanges: hasUnsavedChanges
        )
    }

    private var groupedBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .systemGroupedBackground)
            : Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($draftItems) { $item in
                        HStack(spacing: 12) {
                            Image(systemName: item.kind.iconSymbolName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.accentColor)
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)

                            Text(item.kind.localizedTitle)
                                .font(.body)
                                .foregroundColor(.primary)

                            Spacer()

                            Toggle(String(), isOn: $item.isVisible)
                                .labelsHidden()
                                .accessibilityLabel(item.kind.localizedTitle)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in
                        draftItems.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text(L10n.overview.overview.customizeOverviewDescription)
                        .textCase(nil)
                }

                Section {
                    Button {
                        draftItems = OverviewSectionItemConfig.defaultConfig
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 15, weight: .medium))
                            Text(L10n.overview.overview.resetToDefault)
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L10n.overview.overview.customizeOverview)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MistiaGuardedDismissButton(
                        configuration: dismissGuardConfiguration
                    )
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? Color.white : Color(red: 0.15, green: 0.08, blue: 0.30))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(MistiaAccent.purple.color)
                    .accessibilityLabel(L10n.common.save)
                }
            }
            .toolbarBackground(groupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(groupedBackground)
        .onAppear {
            draftItems = items
            initialItems = items
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
    }

    private func save() {
        items = draftItems
        dismiss()
    }
}

#Preview {
    OverviewWidgetManagementSheet(
        items: .constant(OverviewSectionItemConfig.defaultConfig)
    )
}
