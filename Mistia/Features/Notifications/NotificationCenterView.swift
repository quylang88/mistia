import SwiftData
import SwiftUI

struct NotificationCenterView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState
    
    @Query(sort: \AppNotificationRecord.createdAt, order: .reverse)
    private var rows: [AppNotificationRecord]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil && !$0.isArchived })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil && !$0.isArchived })
    private var storedBills: [RecurringBillPlan]

    private struct StatementTarget: Identifiable, Hashable {
        let wallet: LedgerWallet
        let month: Date?
        var id: String { "\(wallet.id.uuidString)-\(month?.timeIntervalSince1970 ?? 0)" }
    }

    @State private var viewID = UUID()
    @State private var statementTarget: StatementTarget?
    @State private var duePaymentTarget: DuePaymentSheetTarget?
    @State private var duePaymentOriginRow: AppNotificationRecord?
    @State private var transferTarget: TransactionEditorTarget?
    @State private var responseErrorAlert: NotificationResponseErrorAlert?

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
            onRefresh: { await refreshInbox(triggeredByPull: true) },
            pinnedHeader: { EmptyView() },
            trailingAccessory: { trailingMenu },
            content: { content }
        )
        .task {
            await refreshInbox(triggeredByPull: false)
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
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $transferTarget) { target in
            TransactionEditorSheet(target: target)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .alert(item: $responseErrorAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(mistiaLocalized(vi: "OK", en: "OK", ja: "OK")))
            )
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
            ZStack(alignment: .bottom) {
                notificationIcon(row)
                    .frame(width: 32, height: 32)
                    .padding(.bottom, 8)

                unreadDot(for: row)
            }
            .frame(width: 32, height: 42)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(notificationTitle(for: row))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(MistiaDateFormatting.relativeTimeLabel(for: row.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(notificationBody(for: row))
                    .font(.system(size: 14, weight: row.isRead ? .regular : .medium, design: .rounded))
                    .foregroundStyle(row.isRead ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                if row.opensTopUpTransfer {
                    topUpActionRow(for: row)
                        .padding(.top, 4)
                } else if let actionHint = actionHint(for: row) {
                    Text(actionHint)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(actionHintColor(for: row))
                        .padding(.top, 2)
                }

                if row.isRespondableFamilyRequest {
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
                        .tint(notificationPurpleAccent)

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
            row.isRead ? Color.clear : notificationPurpleAccent.opacity(0.07)
        )
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 62)
        }
    }

    @ViewBuilder
    private func unreadDot(for row: AppNotificationRecord) -> some View {
        if !row.isRead {
            Circle()
                .fill(notificationPurpleAccent)
                .frame(width: 8, height: 8)
                .offset(y: 2)
        }
    }

    @ViewBuilder
    private func notificationIcon(_ row: AppNotificationRecord) -> some View {
        if let bill = billPlan(for: row) {
            let iconSymbolName = bill.category?.iconSymbolName ?? bill.iconSymbolName
            let iconColorHex = bill.category?.iconColorHex ?? MistiaFinanceIconRegistry.defaultColorHex(for: iconSymbolName)
            MistiaFinanceIconView(
                icon: iconSymbolName,
                fallbackColor: Color(hex: iconColorHex),
                size: 32
            )
        } else if let category = categoryResource(for: row) {
            MistiaFinanceIconView(
                icon: category.iconSymbolName,
                fallbackColor: Color(hex: category.iconColorHex),
                size: 32
            )
        } else if let wallet = walletResource(for: row) {
            MistiaFinanceIconView(
                icon: wallet.iconSymbolName,
                fallbackColor: Color(hex: wallet.iconColorHex),
                size: 32
            )
        } else {
            let config = iconConfig(for: row)
            ZStack {
                Circle()
                    .fill(config.color.opacity(0.12))

                if let assetName = config.assetName {
                    Image(assetName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(config.color)
                } else {
                    Image(systemName: config.systemImage ?? "bell.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(config.color)
                }
            }
        }
    }

    private func topUpActionRow(for row: AppNotificationRecord) -> some View {
        Button {
            handleRowTap(row)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 12, weight: .bold))

                Text(
                    mistiaLocalized(
                        vi: "Chạm vào để nạp tiền vào ví",
                        en: "Tap to add funds to wallet",
                        ja: "タップしてウォレットに入金"
                    )
                )
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.orange.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 14, tint: .orange))
    }

    private struct IconConfig {
        let systemImage: String?
        let assetName: String?
        let color: Color

        init(systemImage: String? = nil, assetName: String? = nil, color: Color) {
            self.systemImage = systemImage
            self.assetName = assetName
            self.color = color
        }
    }

    private func iconConfig(for row: AppNotificationRecord) -> IconConfig {
        switch row.kind {
        case .dueSoon, .billPaymentRequired, .billOverdue:
            return IconConfig(systemImage: "calendar.badge.clock", color: .orange)
        case .budgetWarning:
            return IconConfig(systemImage: "chart.pie.fill", color: .mint)
        case .creditCardStatementReady:
            return IconConfig(systemImage: "doc.text.fill", color: notificationPurpleAccent)
        case .creditCardAutoPaymentFailed, .billAutoPaymentFailed:
            return IconConfig(systemImage: "exclamationmark.triangle.fill", color: .red)
        case .creditCardAutoPaymentSucceeded, .billAutoPaymentSucceeded:
            return IconConfig(systemImage: "checkmark.circle.fill", color: .green)
        case .lowWallet:
            return IconConfig(systemImage: "tray.and.arrow.down.fill", color: .orange)
        case .permissionRequestReceived, .familyTransactionRequestReceived:
            return IconConfig(assetName: "ic_fluent_shield_checkmark_24_color", color: notificationPurpleAccent)
        case .permissionRequestApproved,
             .familyTransactionRequestApproved:
            return IconConfig(assetName: "ic_fluent_checkmark_circle_24_color", color: .green)
        case .permissionRequestRejected,
             .familyTransactionRequestRejected:
            return IconConfig(systemImage: "xmark.circle.fill", color: .red)
        case .permissionRevoked,
             .permissionPolicyChanged:
            return IconConfig(assetName: "ic_fluent_lock_shield_24_color", color: notificationPurpleAccent)
        case .familyActivity:
            return IconConfig(assetName: "ic_fluent_people_team_24_color", color: .blue)
        case .accessIssue:
            return IconConfig(systemImage: "lock.fill", color: .red)
        case .familyPlaceholder:
            return IconConfig(systemImage: "bell.fill", color: .secondary)
        }
    }

    private func handleRowTap(_ row: AppNotificationRecord) {
        markAsRead(row)

        if row.isRespondableFamilyRequest {
            // Wait for user to tap specific action buttons
            return
        }

        if handleFamilyActivityTap(row) {
            return
        }

        if let transferTarget = makeTransferTarget(for: row) {
            self.transferTarget = transferTarget
            return
        }

        if let payload = row.dueActionPayload, row.opensDuePaymentSheet {
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
        } else if row.opensCreditCardStatement, row.resourceType == .card, let walletID = row.resourceID {
            if let wallet = storedWallets.first(where: { $0.id == walletID }) {
                let monthHint = row.creditCardActionPayload
                    .flatMap { PlanningLogic.month(from: $0.statementMonthKey, calendar: calendar) }
                    ?? row.dueActionPayload?.dueDate
                    ?? row.createdAt
                statementTarget = StatementTarget(
                    wallet: wallet,
                    month: PlanningLogic.startOfMonth(for: monthHint, calendar: calendar)
                )
            }
        }
    }

    private func handleFamilyActivityTap(_ row: AppNotificationRecord) -> Bool {
        guard row.kind == .familyActivity else {
            return false
        }

        Task { @MainActor in
            _ = await sessionStore.syncFamilyActivityChanges()
            familyContextStore.activateSelfView()
            uiState.requestTabSelection(familyActivityTargetTab(for: row.resourceType))
            dismiss()
        }
        return true
    }

    private func familyActivityTargetTab(
        for resourceType: MistiaFamilyNotificationResourceType?
    ) -> MistiaTab {
        switch resourceType {
        case .transaction:
            return .transactions
        case .wallet, .category:
            return .settings
        case .budget, .goal, .card, .debt, .bill, .due, .installment:
            return .planning
        case .permission, nil:
            return .settings
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
        let snapshot = NotificationResponseSnapshot(row: row)
        applyImmediatePermissionResponse(to: row, approve: approve)

        Task {
            let didRespond = await familyContextStore.respondToPermissionNotification(
                row,
                approve: approve,
                sessionStore: sessionStore
            )
            guard !didRespond else { return }

            await MainActor.run {
                snapshot.restore(row)
                try? modelContext.save()
                responseErrorAlert = NotificationResponseErrorAlert(
                    title: mistiaLocalized(
                        vi: "Chưa thể phản hồi",
                        en: "Couldn't respond",
                        ja: "返信できませんでした"
                    ),
                    message: familyContextStore.lastErrorMessage ?? mistiaLocalized(
                        vi: "Mistia chưa gửi được phản hồi. Hãy thử lại sau khi đồng bộ ổn định.",
                        en: "Mistia couldn't send this response yet. Try again when sync is stable.",
                        ja: "まだ返信を送信できません。同期が安定してからもう一度お試しください。"
                    )
                )
            }
        }
    }

    private func applyImmediatePermissionResponse(to row: AppNotificationRecord, approve: Bool) {
        row.title = resolvedPermissionRequestTitle(for: row, approve: approve)
        row.body = resolvedPermissionRequestBody(approve: approve)
        row.actionState = approve ? .approved : .rejected
        row.isRead = true
        row.readAt = row.readAt ?? .now
        row.updatedAt = .now
        if row.source == .family {
            row.needsReadSync = true
        }
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: approve ? .light : .soft).impactOccurred()
    }

    private func notificationTitle(for row: AppNotificationRecord) -> String {
        switch row.kind {
        case .permissionRequestReceived, .familyTransactionRequestReceived:
            if row.actionState == .approved {
                return resolvedPermissionRequestTitle(for: row, approve: true)
            } else if row.actionState == .rejected {
                return resolvedPermissionRequestTitle(for: row, approve: false)
            }
            return row.title
            
        case .permissionRequestApproved, .familyTransactionRequestApproved:
            let resource = row.resourceType?.localizedName ?? mistiaLocalized(vi: "truy cập", en: "access", ja: "アクセス")
            let scope = row.permissionScope?.localizedActionName ?? ""
            let action = mistiaLocalized(vi: "đã được chấp thuận", en: "approved", ja: "が承認されました")
            
            if !scope.isEmpty {
                return mistiaLocalized(
                    vi: "Yêu cầu \(scope) \(resource) \(action)",
                    en: "\(resource) \(scope) request \(action)",
                    ja: "\(resource)の\(scope)リクエスト\(action)"
                )
            }
            return mistiaLocalized(
                vi: "Yêu cầu \(resource) \(action)",
                en: "\(resource) request \(action)",
                ja: "\(resource)のリクエスト\(action)"
            )
            
        case .permissionRequestRejected, .familyTransactionRequestRejected:
            let resource = row.resourceType?.localizedName ?? mistiaLocalized(vi: "truy cập", en: "access", ja: "アクセス")
            let scope = row.permissionScope?.localizedActionName ?? ""
            let action = mistiaLocalized(vi: "bị từ chối", en: "rejected", ja: "が拒否されました")
            
            if !scope.isEmpty {
                return mistiaLocalized(
                    vi: "Yêu cầu \(scope) \(resource) \(action)",
                    en: "\(resource) \(scope) request \(action)",
                    ja: "\(resource)の\(scope)リクエスト\(action)"
                )
            }
            return mistiaLocalized(
                vi: "Yêu cầu \(resource) \(action)",
                en: "\(resource) request \(action)",
                ja: "\(resource)のリクエスト\(action)"
            )
            
        case .permissionRevoked:
            let resource = row.resourceType?.localizedName ?? mistiaLocalized(vi: "truy cập", en: "access", ja: "アクセス")
            return mistiaLocalized(
                vi: "Đã thu hồi quyền \(resource)",
                en: "Revoked \(resource) access",
                ja: "\(resource)の権限が取り消されました"
            )
            
        case .familyActivity:
            if let metadataJSON = row.metadataJSON,
               let data = metadataJSON.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               dict["joined_user_id"] != nil || dict["invite_id"] != nil {
                return mistiaLocalized(vi: "Thành viên mới", en: "New member", ja: "新しいメンバー")
            }
            return row.title

        default:
            return row.title
        }
    }

    private func notificationBody(for row: AppNotificationRecord) -> String {
        switch row.kind {
        case .permissionRequestReceived, .familyTransactionRequestReceived:
            if row.actionState == .approved {
                return resolvedPermissionRequestBody(approve: true)
            } else if row.actionState == .rejected {
                return resolvedPermissionRequestBody(approve: false)
            }
            return row.body
            
        case .permissionRequestApproved, .permissionRequestRejected,
             .familyTransactionRequestApproved, .familyTransactionRequestRejected:
            let actorName = familyContextStore.displayName(for: row.actorUserID)
                ?? mistiaLocalized(vi: "Thành viên", en: "Member", ja: "メンバー")
            
            let isApproved = row.kind == .permissionRequestApproved || row.kind == .familyTransactionRequestApproved
            let action = isApproved
                ? mistiaLocalized(vi: "đã chấp thuận", en: "approved", ja: "が承認しました")
                : mistiaLocalized(vi: "đã từ chối", en: "rejected", ja: "が拒否しました")
            
            let scope = row.permissionScope?.localizedActionName ?? ""
            let resourceType = row.resourceType?.localizedName ?? ""
            let resourceName = resolvedResourceName(for: row) ?? ""
            let resourceDetail = resourceName.isEmpty ? resourceType : "\(resourceType) (\(resourceName))"
            
            if !scope.isEmpty {
                return mistiaLocalized(
                    vi: "\(actorName) \(action) yêu cầu \(scope) \(resourceDetail) của bạn.",
                    en: "\(actorName) \(action) your \(scope) \(resourceDetail) request.",
                    ja: "\(actorName)があなたの\(scope) \(resourceDetail)のリクエスト\(action)。"
                )
            }
            return mistiaLocalized(
                vi: "\(actorName) \(action) yêu cầu \(resourceDetail) của bạn.",
                en: "\(actorName) \(action) your \(resourceDetail) request.",
                ja: "\(actorName)があなたの\(resourceDetail)のリクエスト\(action)。"
            )
            
        case .permissionRevoked:
            let actorName = familyContextStore.displayName(for: row.actorUserID)
                ?? mistiaLocalized(vi: "Chủ sở hữu", en: "The owner", ja: "所有者")
            let resourceType = row.resourceType?.localizedName ?? ""
            if let resourceName = resolvedResourceName(for: row) {
                return mistiaLocalized(
                    vi: "\(actorName) đã thu hồi quyền sử dụng \(resourceType) (\(resourceName)) của bạn.",
                    en: "\(actorName) revoked your access to \(resourceType) (\(resourceName)).",
                    ja: "\(actorName)があなたの\(resourceType) (\(resourceName)) の使用権限を取り消しました。"
                )
            }
            return row.body
            
        case .familyActivity:
            let actorName = familyContextStore.displayName(for: row.actorUserID)
                ?? mistiaLocalized(vi: "Một thành viên", en: "A member", ja: "メンバー")
            
            if let metadataJSON = row.metadataJSON,
               let data = metadataJSON.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                
                if dict["joined_user_id"] != nil || dict["invite_id"] != nil {
                    // This is a join notification. Use backend body which is already good.
                    return row.body
                }
                
                if let actionRaw = dict["action"] {
                    let actionLabel: String
                    switch actionRaw {
                    case "created": actionLabel = mistiaLocalized(vi: "vừa tạo mới", en: "created", ja: "作成")
                    case "updated": actionLabel = mistiaLocalized(vi: "vừa cập nhật", en: "updated", ja: "更新")
                    case "deleted": actionLabel = mistiaLocalized(vi: "vừa xóa", en: "deleted", ja: "削除")
                    default: actionLabel = mistiaLocalized(vi: "vừa thay đổi", en: "changed", ja: "変更")
                    }
                    
                    let resourceType = row.resourceType?.localizedName ?? ""
                    let resourceName = resolvedResourceName(for: row) ?? ""
                    let resourceDetail = resourceName.isEmpty ? resourceType : "\(resourceType) (\(resourceName))"
                    
                    if let amountMinorStr = dict["amount_minor"],
                       let amountMinor = Int64(amountMinorStr),
                       let currencyCode = dict["currency_code"] {
                        let amountText = amountMinor.formattedCurrency(code: currencyCode)
                        return mistiaLocalized(
                            vi: "\(actorName) \(actionLabel) \(resourceDetail) trị giá \(amountText).",
                            en: "\(actorName) \(actionLabel) \(resourceDetail) worth \(amountText).",
                            ja: "\(actorName)が \(amountText) の \(resourceDetail) を\(actionLabel)しました。"
                        )
                    }
                    
                    return mistiaLocalized(
                        vi: "\(actorName) \(actionLabel) \(resourceDetail) của bạn.",
                        en: "\(actorName) \(actionLabel) your \(resourceDetail).",
                        ja: "\(actorName)があなたの \(resourceDetail) を\(actionLabel)しました。"
                    )
                }
            }
            return row.body

        default:
            return row.body
        }
    }

    private func resolvedResourceName(for row: AppNotificationRecord) -> String? {
        if let wallet = walletResource(for: row) {
            return wallet.name
        }
        if let category = categoryResource(for: row) {
            return category.name
        }
        if let bill = billPlan(for: row) {
            return bill.name
        }
        
        if let metadataJSON = row.metadataJSON,
           let data = metadataJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict["wallet_name"] as? String
                ?? dict["category_name"] as? String
                ?? dict["bill_name"] as? String
                ?? dict["transaction_title"] as? String
                ?? dict["goal_name"] as? String
                ?? dict["installment_name"] as? String
        }
        
        return nil
    }

    private func resolvedPermissionRequestTitle(for row: AppNotificationRecord, approve: Bool) -> String {
        let name = permissionRequesterName(for: row)
        let action = approve
            ? mistiaLocalized(vi: "Đã chấp thuận", en: "Approved", ja: "承認済み")
            : mistiaLocalized(vi: "Đã từ chối", en: "Rejected", ja: "拒否済み")
        let resource = row.resourceType?.localizedName ?? mistiaLocalized(vi: "truy cập", en: "access", ja: "アクセス")
        let scope = row.permissionScope?.localizedActionName ?? ""
        
        if !scope.isEmpty {
            return mistiaLocalized(
                vi: "\(action) yêu cầu \(scope) \(resource) của \(name)",
                en: "\(action) \(name)'s \(scope) \(resource) request",
                ja: "\(name)さんの\(resource)の\(scope)リクエストを\(action)しました"
            )
        }
        
        return mistiaLocalized(
            vi: "\(action) yêu cầu \(resource) của \(name)",
            en: "\(action) \(name)'s \(resource) request",
            ja: "\(name)さんの\(resource)のリクエストを\(action)しました"
        )
    }

    private func resolvedPermissionRequestBody(approve: Bool) -> String {
        approve
            ? mistiaLocalized(
                vi: "Mistia sẽ âm thầm đồng bộ thay đổi lên cloud.",
                en: "Mistia will sync the change to cloud in the background.",
                ja: "Mistia がバックグラウンドでクラウドへ同期します。"
            )
            : mistiaLocalized(
                vi: "Không có thay đổi nào được đẩy lên cloud.",
                en: "No change will be pushed to cloud.",
                ja: "クラウドへ変更は送信されません。"
            )
    }

    private func permissionRequesterName(for row: AppNotificationRecord) -> String {
        familyContextStore.displayName(for: row.actorUserID)
            ?? mistiaLocalized(vi: "thành viên", en: "this member", ja: "このメンバー")
    }

    private func actionHint(for row: AppNotificationRecord) -> String? {
        if row.opensCreditCardStatement {
            return mistiaLocalized(
                vi: "Chạm để mở sao kê và thanh toán",
                en: "Tap to open the statement and pay",
                ja: "タップして明細を開いて支払う"
            )
        }

        if row.opensDuePaymentSheet {
            return mistiaLocalized(
                vi: "Chạm để thanh toán",
                en: "Tap to pay",
                ja: "タップして支払う"
            )
        }

        return nil
    }

    private func actionHintColor(for row: AppNotificationRecord) -> Color {
        notificationPurpleAccent
    }

    private func makeTransferTarget(for row: AppNotificationRecord) -> TransactionEditorTarget? {
        guard let destinationWalletID = row.topUpTransferDestinationWalletID else {
            return nil
        }

        return TransactionEditorTarget(
            initialKind: .transfer,
            transferPreset: TransactionTransferPreset(destinationWalletID: destinationWalletID)
        )
    }

    private func refreshInbox(triggeredByPull: Bool) async {
        if triggeredByPull {
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        await MistiaDueMaintenance.run(
            modelContext: modelContext,
            sessionStore: sessionStore,
            referenceDate: .now,
            calendar: calendar
        )
        await familyContextStore.refreshNotifications(sessionStore: sessionStore)
    }

    private var notificationPurpleAccent: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    private func billPlan(for row: AppNotificationRecord) -> RecurringBillPlan? {
        guard row.resourceType == .bill, let resourceID = row.resourceID else {
            return nil
        }

        return storedBills.first(where: { $0.id == resourceID })
    }

    private func categoryResource(for row: AppNotificationRecord) -> TransactionCategory? {
        guard row.resourceType == .category,
              let resourceID = row.resourceID else {
            return nil
        }

        return storedCategories.first(where: { $0.id == resourceID })
    }

    private func walletResource(for row: AppNotificationRecord) -> LedgerWallet? {
        guard let resourceID = row.resourceID else {
            return nil
        }

        switch row.resourceType {
        case .card, .wallet:
            return storedWallets.first(where: { $0.id == resourceID })
        default:
            return nil
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

private struct NotificationResponseErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct NotificationResponseSnapshot {
    let title: String
    let body: String
    let actionState: MistiaNotificationActionState
    let isRead: Bool
    let readAt: Date?
    let updatedAt: Date
    let needsReadSync: Bool

    init(row: AppNotificationRecord) {
        title = row.title
        body = row.body
        actionState = row.actionState
        isRead = row.isRead
        readAt = row.readAt
        updatedAt = row.updatedAt
        needsReadSync = row.needsReadSync
    }

    func restore(_ row: AppNotificationRecord) {
        row.title = title
        row.body = body
        row.actionState = actionState
        row.isRead = isRead
        row.readAt = readAt
        row.updatedAt = updatedAt
        row.needsReadSync = needsReadSync
    }
}

private extension AppNotificationRecord {
    var opensCreditCardStatement: Bool {
        switch kind {
        case .creditCardStatementReady:
            return true
        default:
            return false
        }
    }

    var opensDuePaymentSheet: Bool {
        switch kind {
        case .billPaymentRequired, .billOverdue:
            return true
        default:
            return false
        }
    }

    var opensTopUpTransfer: Bool {
        topUpTransferDestinationWalletID != nil
    }

    var isRespondableFamilyRequest: Bool {
        switch kind {
        case .permissionRequestReceived:
            return actionState == .pending
        default:
            return false
        }
    }
}
