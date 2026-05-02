import SwiftData
import SwiftUI

struct NotificationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState
    
    @Query(sort: \AppNotificationRecord.createdAt, order: .reverse)
    private var rows: [AppNotificationRecord]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil && !$0.isArchived })
    private var storedWallets: [LedgerWallet]

    @State private var viewID = UUID()
    @State private var statementWallet: LedgerWallet?

    private var visibleRows: [AppNotificationRecord] {
        MistiaNotificationStore.visibleRows(
            rows,
            userID: sessionStore.activeLocalProfileUserID
        )
    }

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
        .task {
            markVisibleAsRead()
        }
        .onAppear {
            uiState.requestQuickCreateHidden(true, id: viewID)
        }
        .onDisappear {
            uiState.requestQuickCreateHidden(false, id: viewID)
        }
        .navigationDestination(item: $statementWallet) { wallet in
            ManagementCreditCardStatementView(wallet: wallet)
        }
    }

    private var trailingMenu: some View {
        MistiaHeaderCircleMenu(label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }) {
            Button {
                markAllAsRead()
            } label: {
                Label(
                    mistiaLocalized(vi: "Đọc hết", en: "Mark all as read", ja: "すべて既読"),
                    systemImage: "envelope.open"
                )
            }
        }
        .accessibilityLabel(mistiaLocalized(vi: "Tác vụ thông báo", en: "Notification actions", ja: "通知アクション"))
    }

    private var content: some View {
        Group {
            if visibleRows.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(visibleRows) { row in
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
                    vi: "Yêu cầu quyền và hoạt động gia đình sẽ xuất hiện tại đây sau khi đồng bộ.",
                    en: "Permission requests and family activity will appear here after sync.",
                    ja: "権限リクエストと家族のアクティビティは同期後にここに表示されます。"
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

                if row.kind == .permissionRequestReceived, row.actionState == .pending {
                    HStack(spacing: 10) {
                        Button {
                            respond(to: row, approve: true)
                        } label: {
                            Label(
                                mistiaLocalized(vi: "Chấp thuận", en: "Approve", ja: "承認"),
                                systemImage: "checkmark.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(MistiaAccent.purple.color)

                        Button(role: .destructive) {
                            respond(to: row, approve: false)
                        } label: {
                            Label(
                                mistiaLocalized(vi: "Từ chối", en: "Reject", ja: "拒否"),
                                systemImage: "xmark.circle"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                } else if row.kind == .dueSoon, row.resourceType == .card, let walletID = row.resourceID {
                    Button {
                        if let wallet = storedWallets.first(where: { $0.id == walletID }) {
                            statementWallet = wallet
                        }
                    } label: {
                        Label(
                            mistiaLocalized(vi: "Thanh toán ngay", en: "Pay now", ja: "今すぐ支払う"),
                            systemImage: "creditcard.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(MistiaAccent.purple.color)
                    .padding(.top, 4)
                }
            }
        }
        .padding(14)
        .background(
            (row.isRead ? Color(UIColor.secondarySystemGroupedBackground).opacity(0.35) : Color(UIColor.secondarySystemGroupedBackground).opacity(0.70)),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
    
    private func markAsRead(_ row: AppNotificationRecord) {
        guard let remoteIDs = try? MistiaNotificationStore.markAsRead([row], in: modelContext),
              !remoteIDs.isEmpty else { return }
        Task {
            await familyContextStore.pushNotificationReadState(sessionStore: sessionStore)
        }
    }
    
    private func markAllAsRead() {
        guard let remoteIDs = try? MistiaNotificationStore.markAllAsRead(
            for: sessionStore.activeLocalProfileUserID,
            in: modelContext
        ), !remoteIDs.isEmpty else {
            return
        }

        Task {
            await familyContextStore.pushNotificationReadState(sessionStore: sessionStore)
        }
    }

    private func markVisibleAsRead() {
        guard let remoteIDs = try? MistiaNotificationStore.markAsRead(visibleRows, in: modelContext),
              !remoteIDs.isEmpty else { return }
        Task {
            await familyContextStore.pushNotificationReadState(sessionStore: sessionStore)
        }
    }

    private func respond(to row: AppNotificationRecord, approve: Bool) {
        Task {
            await familyContextStore.respondToPermissionNotification(
                row,
                approve: approve,
                sessionStore: sessionStore
            )
        }
    }
}

struct MistiaNotificationBellButton: View {
    @Environment(SessionStore.self) private var sessionStore
    @Query private var rows: [AppNotificationRecord]

    let action: () -> Void

    private var unreadCount: Int {
        MistiaNotificationStore.unreadCount(
            rows: rows,
            userID: sessionStore.activeLocalProfileUserID
        )
    }

    var body: some View {
        MistiaHeaderCircleButton(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)

                if unreadCount > 0 {
                    Text(badgeText)
                        .font(.system(size: unreadCount > 99 ? 7 : 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, unreadCount > 9 ? 3 : 0)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(MistiaAccent.expense.color, in: Capsule())
                        .offset(x: 9, y: -9)
                        .accessibilityLabel(
                            mistiaLocalized(
                                vi: "\(unreadCount) thông báo chưa đọc",
                                en: "\(unreadCount) unread notifications",
                                ja: "未読通知 \(unreadCount) 件"
                            )
                        )
                }
            }
        }
    }

    private var badgeText: String {
        unreadCount > 99 ? "99+" : "\(unreadCount)"
    }
}
