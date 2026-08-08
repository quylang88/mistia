import SwiftUI

struct OverviewWidgetManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var items: [OverviewSectionItemConfig]

    var onResetToDefault: () -> Void

    private var groupedBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .systemGroupedBackground)
            : Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($items) { $item in
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

                            Toggle("", isOn: $item.isVisible)
                                .labelsHidden()
                                .accessibilityLabel(item.kind.localizedTitle)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in
                        items.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Bật/tắt và sắp xếp thứ tự hiển thị các section bên dưới màn hình Tổng quan.")
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L10n.overview.overview.customizeOverview)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onResetToDefault()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(L10n.overview.overview.resetToDefault)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(L10n.overview.overview.done)
                }
            }
            .toolbarBackground(groupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(groupedBackground)
    }
}

#Preview {
    OverviewWidgetManagementSheet(
        items: .constant(OverviewSectionItemConfig.defaultConfig),
        onResetToDefault: {}
    )
}
