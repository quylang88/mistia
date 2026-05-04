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

    private struct StatementTarget: Identifiable, Hashable {
        let wallet: LedgerWallet
        let month: Date?
        var id: String { "\(wallet.id.uuidString)-\(month?.timeIntervalSince1970 ?? 0)" }
    }

    @State private var viewID = UUID()
    @State private var statementTarget: StatementTarget?
    @State private var duePaymentTarget: DuePaymentSheetTarget?
    @State private var duePaymentOriginRow: AppNotificationRecord?

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
            await familyContextStore.refreshNotifications(sessionStore: sessionStore)
        }
        .onAppear {
            uiState.requestQuickCreateHidden(true, id: viewID)
        }
        .onDisappear {
            uiState.requestQuickCreateHidden(false, id: viewID)
        }
        .navigationDestination(item: $statementTarget) { target in
            ManagementCreditCardStatementView(wallet: target.wallet, initialMonth: target.month)
        }
        .sheet(item: $duePaymentTarget) { target in
            DuePaymentSheet(target: target) {
                if let row = duePaymentOriginRow {
                    row.actionState = .resolved
                    markAsRead(row)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
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
                VStack(spacing: 0) {
                    ForEach(visibleRows) { row in
                        notificationRow(row)
                            .onTapGesture { handleRowTap(row) }
                    }
                }
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
        HStack(alignment: .top, spacing: 14) {
            notificationIcon(row)
                .frame(width: 32, height: 32)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(row.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(MistiaDateFormatting.relativeTimeLabel(for: row.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(row.body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

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
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            row.isRead ? Color.clear : MistiaAccent.purple.color.opacity(0.04)
        )
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 62)
        }
    }

    @ViewBuilder
    private func notificationIcon(_ row: AppNotificationRecord) -> some View {
        let config = iconConfig(for: row)
        ZStack {
            Circle()
                .fill(config.color.opacity(0.12))

            Image(systemName: config.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(config.color)
        }
    }

    private struct IconConfig {
        let systemImage: String
        let color: Color
    }

    private func iconConfig(for row: AppNotificationRecord) -> IconConfig {
        switch row.kind {
        case .dueSoon, .billPaymentRequired, .billOverdue:
            return IconConfig(systemImage: "calendar.badge.clock", color: .orange)
        case .creditCardStatementReady:
            return IconConfig(systemImage: "doc.text.fill", color: MistiaAccent.purple.color)
        case .creditCardAutoPaymentFailed, .billAutoPaymentFailed:
            return IconConfig(systemImage: "exclamationmark.triangle.fill", color: .red)
        case .creditCardAutoPaymentSucceeded, .billAutoPaymentSucceeded:
            return IconConfig(systemImage: "checkmark.circle.fill", color: .green)
        case .lowWallet:
            return IconConfig(systemImage: "tray.and.arrow.down.fill", color: .orange)
        case .permissionRequestReceived:
            return IconConfig(systemImage: "person.badge.key.fill", color: MistiaAccent.purple.color)
        case .permissionRequestApproved, .permissionRequestRejected, .permissionRevoked, .permissionPolicyChanged:
            return IconConfig(systemImage: "shield.fill", color: MistiaAccent.purple.color)
        case .familyActivity:
            return IconConfig(systemImage: "person.2.fill", color: .blue)
        case .accessIssue:
            return IconConfig(systemImage: "lock.fill", color: .red)
        case .familyPlaceholder:
            return IconConfig(systemImage: "bell.fill", color: .secondary)
        }
    }

    private func handleRowTap(_ row: AppNotificationRecord) {
        markAsRead(row)

        if row.kind == .permissionRequestReceived, row.actionState == .pending {
            // Wait for user to tap specific action buttons
            return
        }

        if let payload = row.dueActionPayload, row.actionState == .pending {
            duePaymentOriginRow = row
            duePaymentTarget = DuePaymentSheetTarget(
                sourceKind: PlanningDueSourceKind(rawValue: payload.sourceKind) ?? .recurringBill,
                sourceID: payload.sourceID,
                dueMonthKey: payload.dueMonthKey,
                dueDate: payload.dueDate,
                requiresAmountInput: payload.requiresAmountInput,
                currencyCode: payload.currencyCode,
                name: payload.billName
            )
        } else if row.isCreditCardPaymentNotification, row.resourceType == .card, let walletID = row.resourceID {
            if let wallet = storedWallets.first(where: { $0.id == walletID }) {
                let monthHint = (row.dueActionPayload?.dueDate) ?? row.createdAt
                statementTarget = StatementTarget(
                    wallet: wallet,
                    month: PlanningLogic.startOfMonth(for: monthHint)
                )
            }
        }
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

private extension AppNotificationRecord {
    var isCreditCardPaymentNotification: Bool {
        switch kind {
        case .dueSoon, .creditCardStatementReady, .creditCardAutoPaymentFailed:
            return true
        case .lowWallet, .creditCardAutoPaymentSucceeded, .familyPlaceholder, .permissionRequestReceived, .permissionRequestApproved, .permissionRequestRejected, .permissionRevoked, .permissionPolicyChanged, .familyActivity, .accessIssue, .billPaymentRequired, .billAutoPaymentFailed, .billOverdue, .billAutoPaymentSucceeded:
            return false
        }
    }
}
