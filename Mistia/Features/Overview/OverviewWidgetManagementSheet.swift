import SwiftUI

struct OverviewWidgetManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var items: [OverviewSectionItemConfig]

    var onResetToDefault: () -> Void

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

                            Text(item.kind.localizedTitle)
                                .font(.body)
                                .foregroundColor(.primary)

                            Spacer()

                            Toggle("", isOn: $item.isVisible)
                                .labelsHidden()
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
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Tùy chỉnh Tổng quan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Khôi phục") {
                        onResetToDefault()
                    }
                    .foregroundColor(.secondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
