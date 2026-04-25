import SwiftData
import SwiftUI

struct NotificationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \AppNotificationRecord.createdAt, order: .reverse)
    private var rows: [AppNotificationRecord]

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Thông báo", en: "Notifications", ja: "通知"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            pinnedHeader: { EmptyView() },
            trailingAccessory: { trailingMenu },
            content: { content }
        )
    }

    private var trailingMenu: some View {
        Menu {
            Button {
                markAllAsRead()
            } label: {
                Label(
                    mistiaLocalized(vi: "Đọc hết", en: "Mark all as read", ja: "すべて既読"),
                    systemImage: "checkmark.circle"
                )
            }
        } label: {
            MistiaHeaderCircleButton(action: {}) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            }
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .buttonStyle(.plain)
    }

    private var content: some View {
        Group {
            if rows.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(rows) { row in
                        notificationRow(row)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onTapGesture { markAsRead(row) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(mistiaLocalized(
                    vi: "Chưa có thông báo",
                    en: "No notifications yet",
                    ja: "通知はまだありません"
                ))
                .font(.system(.headline, design: .rounded))

                Text(mistiaLocalized(
                    vi: "Khi bạn bật Nhắc nhở, Mistia sẽ hiển thị thông báo ở đây.",
                    en: "When you enable Reminders, Mistia will show notifications here.",
                    ja: "リマインダーを有効にすると、ここに通知が表示されます。"
                ))
                .descriptionTextStyle()
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                Color(UIColor.secondarySystemGroupedBackground).opacity(0.62),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
    }
    
    @ViewBuilder
    private func notificationRow(_ row: AppNotificationRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(row.isRead ? Color.clear : MistiaAccent.purple.color)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .overlay {
                    if row.isRead {
                        Circle()
                            .stroke(Color(UIColor.systemGray4), lineWidth: 1)
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 10)
                    Text(MistiaDateFormatting.dateTimeString(for: row.createdAt))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(row.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            (row.isRead ? Color(UIColor.secondarySystemGroupedBackground).opacity(0.35) : Color(UIColor.secondarySystemGroupedBackground).opacity(0.70)),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
    
    private func markAsRead(_ row: AppNotificationRecord) {
        guard !row.isRead else { return }
        row.isRead = true
        row.updatedAt = .now
        try? modelContext.save()
    }
    
    private func markAllAsRead() {
        var changed = false
        for row in rows where !row.isRead {
            row.isRead = true
            row.updatedAt = .now
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
    }
}

