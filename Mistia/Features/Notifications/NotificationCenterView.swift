import SwiftData
import SwiftUI
import UIKit

struct NotificationCenterResourceIndex {
    private let walletsByID: [UUID: LedgerWallet]
    private let categoriesByID: [UUID: TransactionCategory]
    private let billsByID: [UUID: RecurringBillPlan]

    init(
        wallets: [LedgerWallet],
        categories: [TransactionCategory],
        bills: [RecurringBillPlan]
    ) {
        var walletsByID: [UUID: LedgerWallet] = [:]
        walletsByID.reserveCapacity(wallets.count)
        for wallet in wallets {
            walletsByID[wallet.id] = wallet
        }

        var categoriesByID: [UUID: TransactionCategory] = [:]
        categoriesByID.reserveCapacity(categories.count)
        for category in categories {
            categoriesByID[category.id] = category
        }

        var billsByID: [UUID: RecurringBillPlan] = [:]
        billsByID.reserveCapacity(bills.count)
        for bill in bills {
            billsByID[bill.id] = bill
        }

        self.walletsByID = walletsByID
        self.categoriesByID = categoriesByID
        self.billsByID = billsByID
    }

    func wallet(id: UUID?, resourceType: MistiaFamilyNotificationResourceType?) -> LedgerWallet? {
        guard let id else {
            return nil
        }

        switch resourceType {
        case .card, .wallet:
            return walletsByID[id]
        default:
            return nil
        }
    }

    func wallet(id: UUID?) -> LedgerWallet? {
        guard let id else {
            return nil
        }

        return walletsByID[id]
    }

    func category(id: UUID?, resourceType: MistiaFamilyNotificationResourceType?) -> TransactionCategory? {
        guard resourceType == .category, let id else {
            return nil
        }

        return categoriesByID[id]
    }

    func bill(id: UUID?, resourceType: MistiaFamilyNotificationResourceType?) -> RecurringBillPlan? {
        guard resourceType == .bill, let id else {
            return nil
        }

        return billsByID[id]
    }
}

struct NotificationCenterMetadataIndex {
    private let stringMetadataByRowID: [UUID: [String: String]]
    private let objectMetadataByRowID: [UUID: [String: Any]]

    init(rows: [AppNotificationRecord]) {
        var stringMetadataByRowID: [UUID: [String: String]] = [:]
        var objectMetadataByRowID: [UUID: [String: Any]] = [:]
        stringMetadataByRowID.reserveCapacity(rows.count)
        objectMetadataByRowID.reserveCapacity(rows.count)

        for row in rows {
            guard let metadataJSON = row.metadataJSON,
                  let data = metadataJSON.data(using: .utf8),
                  let metadata = try? JSONSerialization.jsonObject(with: data)
            else {
                continue
            }

            if let objectMetadata = metadata as? [String: Any] {
                objectMetadataByRowID[row.id] = objectMetadata
            }

            if let stringMetadata = metadata as? [String: String] {
                stringMetadataByRowID[row.id] = stringMetadata
            }
        }

        self.stringMetadataByRowID = stringMetadataByRowID
        self.objectMetadataByRowID = objectMetadataByRowID
    }

    func stringMetadata(for row: AppNotificationRecord) -> [String: String]? {
        stringMetadataByRowID[row.id]
    }

    func objectMetadata(for row: AppNotificationRecord) -> [String: Any]? {
        objectMetadataByRowID[row.id]
    }
}

enum NotificationCenterGroupID: String, CaseIterable, Identifiable {
    case actionRequests
    case access
    case familyCashflow
    case familyData
    case bills
    case creditCards
    case wallets
    case budgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actionRequests:
            L10n.notifications.notificationcenter.group.actionRequests
        case .access:
            L10n.notifications.notificationcenter.group.access
        case .familyCashflow:
            L10n.notifications.notificationcenter.group.familyCashflow
        case .familyData:
            L10n.notifications.notificationcenter.group.familyData
        case .bills:
            L10n.notifications.notificationcenter.group.bills
        case .creditCards:
            L10n.notifications.notificationcenter.group.creditCards
        case .wallets:
            L10n.notifications.notificationcenter.group.wallets
        case .budgets:
            L10n.notifications.notificationcenter.group.budgets
        }
    }

    var systemImage: String {
        switch self {
        case .actionRequests:
            "checklist"
        case .access:
            "lock"
        case .familyCashflow:
            "arrow.left.arrow.right.circle"
        case .familyData:
            "person.2"
        case .bills:
            "calendar.badge.clock"
        case .creditCards:
            "creditcard"
        case .wallets:
            "wallet.pass"
        case .budgets:
            "chart.pie"
        }
    }

    var accentColor: Color {
        switch self {
        case .actionRequests:
            MistiaAccent.purple.color
        case .access:
            Color(red: 0.33, green: 0.36, blue: 0.82)
        case .familyCashflow:
            Color(red: 0.18, green: 0.67, blue: 0.62)
        case .familyData:
            Color(red: 0.20, green: 0.49, blue: 0.86)
        case .bills:
            .orange
        case .creditCards:
            Color(red: 0.43, green: 0.23, blue: 0.76)
        case .wallets:
            Color(red: 0.18, green: 0.58, blue: 0.34)
        case .budgets:
            .mint
        }
    }

    var fluentAssetName: String {
        switch self {
        case .actionRequests:
            "ic_fluent_clipboard_task_24_color"
        case .access:
            "ic_fluent_lock_shield_24_color"
        case .familyCashflow:
            "ic_fluent_people_sync_24_color"
        case .familyData:
            "ic_fluent_people_team_24_color"
        case .bills:
            "ic_fluent_calendar_clock_24_color"
        case .creditCards:
            "ic_fluent_credit_card_clock_24_filled"
        case .wallets:
            "ic_fluent_savings_24_color"
        case .budgets:
            "ic_fluent_data_pie_24_color"
        }
    }
}

struct NotificationCenterGroupSummary: Identifiable {
    let id: NotificationCenterGroupID
    let rows: [AppNotificationRecord]
    let latestRow: AppNotificationRecord
    let unreadCount: Int
}

private struct NotificationCenterGroupedRows {
    var rows: [AppNotificationRecord] = []
    var unreadCount = 0

    mutating func append(_ row: AppNotificationRecord) {
        rows.append(row)
        if !row.isRead {
            unreadCount += 1
        }
    }
}

struct NotificationCenterDaySection: Identifiable {
    let id: Date
    let rows: [AppNotificationRecord]
}

struct NotificationCenterDetailSection: Identifiable {
    let id: Date
    let rows: [NotificationCenterDetailRowSnapshot]
}

enum NotificationCenterIconSnapshot {
    case finance(icon: String, colorHex: String)
    case asset(name: String, color: Color)
    case symbol(systemImage: String, color: Color)

    static var fallback: NotificationCenterIconSnapshot {
        .symbol(systemImage: "bell.fill", color: .secondary)
    }
}

enum NotificationCenterDetailAction {
    case permissionResponse
    case primary(title: String, systemImage: String)
}

struct NotificationCenterDetailRowSnapshot: Identifiable {
    let id: UUID
    let key: String
    let createdAt: Date
    let title: String
    let body: String
    let icon: NotificationCenterIconSnapshot
    let action: NotificationCenterDetailAction?
}

struct NotificationCenterDetailItem: Identifiable {
    enum Kind {
        case dayHeader(Date)
        case row(NotificationCenterDetailRowSnapshot)
    }

    let id: String
    let kind: Kind
}

enum NotificationCenterDisplayText {
    private enum FamilyActivityAction: String {
        case created
        case updated
        case deleted
        case familyTransfer = "family_transfer"
    }

    static func permissionResponseBody(approve: Bool) -> String {
        approve
            ? L10n.notifications.notificationcenter.permissionRequestApprovedBody
            : L10n.notifications.notificationcenter.permissionRequestRejectedBody
    }

    static func familyTransferReceivedBody(
        actorName: String,
        walletName: String?,
        amountText: String?,
        fallbackBody: String,
        language: MistiaAppLanguage = .current
    ) -> String {
        let actorName = nonBlank(actorName)
            ?? L10n.notifications.notificationcenter.aMember(language: language)
        let walletName = nonBlank(walletName)
        let amountText = nonBlank(amountText)

        if let walletName, let amountText {
            return L10n.notifications.notificationcenter.valueJustTransferredValueIntoYourValue(
                String(describing: actorName),
                String(describing: amountText),
                String(describing: walletName),
                language: language
            )
        }

        if let walletName {
            return L10n.notifications.notificationcenter.valueJustTransferredMoneyIntoYourValue(
                String(describing: actorName),
                String(describing: walletName),
                language: language
            )
        }

        if let amountText {
            return L10n.notifications.notificationcenter.valueJustTransferredValueToYou(
                String(describing: actorName),
                String(describing: amountText),
                language: language
            )
        }

        return L10n.notifications.notificationcenter.valueSentMoneyToYou(
            String(describing: actorName),
            language: language
        )
    }

    static func familyActivityTitle(
        resourceType: MistiaFamilyNotificationResourceType?,
        actionRaw: String?,
        isMemberJoin: Bool,
        fallbackTitle: String,
        language: MistiaAppLanguage = .current
    ) -> String {
        if isMemberJoin {
            return L10n.notifications.notificationcenter.newMember(language: language)
        }

        guard let actionRaw,
              let action = FamilyActivityAction(rawValue: actionRaw)
        else {
            return nonBlank(fallbackTitle)
                ?? L10n.shared.sync.mistiasynccoordinator.familyActivity(language: language)
        }

        if action == .familyTransfer {
            return L10n.transactions.generatedTitle.familyTransferReceived(language: language)
        }

        switch (resourceType, action) {
        case (.transaction, .created):
            return L10n.shared.sync.mistiasynccoordinator.newTransaction(language: language)
        case (.transaction, .updated):
            return L10n.shared.sync.mistiasynccoordinator.transactionUpdated(language: language)
        case (.transaction, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.transactionDeleted(language: language)
        case (.category, .created), (.category, .updated):
            return L10n.shared.sync.mistiasynccoordinator.categoryUpdated(language: language)
        case (.category, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.categoryDeleted(language: language)
        case (.wallet, .created), (.wallet, .updated):
            return L10n.shared.sync.mistiasynccoordinator.walletUpdated(language: language)
        case (.wallet, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.walletDeleted(language: language)
        case (.budget, .created), (.budget, .updated):
            return L10n.shared.sync.mistiasynccoordinator.budgetUpdated(language: language)
        case (.budget, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.budgetDeleted(language: language)
        case (.goal, .created), (.goal, .updated):
            return L10n.shared.sync.mistiasynccoordinator.goalUpdated(language: language)
        case (.goal, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.goalDeleted(language: language)
        case (.bill, .created), (.bill, .updated):
            return L10n.shared.sync.mistiasynccoordinator.billUpdated(language: language)
        case (.bill, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.billDeleted(language: language)
        case (.installment, .created), (.installment, .updated):
            return L10n.shared.sync.mistiasynccoordinator.installmentUpdated(language: language)
        case (.installment, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.installmentDeleted(language: language)
        default:
            return L10n.shared.sync.mistiasynccoordinator.familyActivity(language: language)
        }
    }

    static func memberJoinedBody(
        actorName: String,
        fallbackBody: String,
        language: MistiaAppLanguage = .current
    ) -> String {
        let actorName = nonBlank(actorName)
            ?? L10n.notifications.notificationcenter.aMember(language: language)
        return L10n.notifications.notificationcenter.valueJoinedTheFamily(
            String(describing: actorName),
            language: language
        )
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum NotificationCenterGrouping {
    static func groupID(for row: AppNotificationRecord) -> NotificationCenterGroupID? {
        switch row.kind {
        case .dueSoon:
            nil

        case .permissionRequestReceived:
            row.actionState == .pending ? .actionRequests : .access

        case .familyTransactionRequestReceived:
            row.actionState == .pending ? .actionRequests : .familyCashflow

        case .permissionRequestApproved,
             .permissionRequestRejected,
             .permissionRevoked,
             .permissionPolicyChanged,
             .accessIssue:
            .access

        case .familyTransactionRequestApproved,
             .familyTransactionRequestRejected:
            .familyCashflow

        case .familyActivity:
            familyActivityGroup(for: row.resourceType)

        case .billPaymentRequired,
             .billAutoPaymentSucceeded,
             .billAutoPaymentFailed,
             .billOverdue:
            .bills

        case .creditCardStatementReady,
             .creditCardAutoPaymentSucceeded,
             .creditCardAutoPaymentFailed:
            .creditCards

        case .lowWallet:
            .wallets

        case .budgetWarning:
            .budgets

        case .familyPlaceholder:
            .familyData
        }
    }

    static func summaries(for rows: [AppNotificationRecord]) -> [NotificationCenterGroupSummary] {
        var rowsByGroup: [NotificationCenterGroupID: NotificationCenterGroupedRows] = [:]
        rowsByGroup.reserveCapacity(NotificationCenterGroupID.allCases.count)

        for row in rows {
            guard let groupID = groupID(for: row) else { continue }
            rowsByGroup[groupID, default: NotificationCenterGroupedRows()].append(row)
        }

        return NotificationCenterGroupID.allCases.compactMap { groupID in
            guard let groupedRows = rowsByGroup[groupID], !groupedRows.rows.isEmpty else { return nil }
            let sortedRows = groupedRows.rows.sorted(by: oldestNotificationFirst)
            guard let latestRow = sortedRows.last else { return nil }
            return NotificationCenterGroupSummary(
                id: groupID,
                rows: sortedRows,
                latestRow: latestRow,
                unreadCount: groupedRows.unreadCount
            )
        }
        .sorted { lhs, rhs in
            newestNotificationFirst(lhs.latestRow, rhs.latestRow)
        }
    }

    static func summary(
        for groupID: NotificationCenterGroupID,
        in rows: [AppNotificationRecord]
    ) -> NotificationCenterGroupSummary? {
        var groupedRows = NotificationCenterGroupedRows()
        groupedRows.rows.reserveCapacity(rows.count)

        for row in rows where self.groupID(for: row) == groupID {
            groupedRows.append(row)
        }

        guard !groupedRows.rows.isEmpty else { return nil }
        let sortedRows = groupedRows.rows.sorted(by: oldestNotificationFirst)
        guard let latestRow = sortedRows.last else { return nil }

        return NotificationCenterGroupSummary(
            id: groupID,
            rows: sortedRows,
            latestRow: latestRow,
            unreadCount: groupedRows.unreadCount
        )
    }

    static func daySections(
        for rows: [AppNotificationRecord],
        calendar: Calendar
    ) -> [NotificationCenterDaySection] {
        var rowsByDay: [Date: [AppNotificationRecord]] = [:]
        rowsByDay.reserveCapacity(rows.count)

        for row in rows {
            rowsByDay[calendar.startOfDay(for: row.createdAt), default: []].append(row)
        }

        return rowsByDay.keys.sorted().map { day in
            NotificationCenterDaySection(
                id: day,
                rows: (rowsByDay[day] ?? []).sorted(by: oldestNotificationFirst)
            )
        }
    }

    static func detailItems(
        for rows: [NotificationCenterDetailRowSnapshot],
        calendar: Calendar
    ) -> [NotificationCenterDetailItem] {
        detailSections(for: rows, calendar: calendar)
            .flatMap { section in
                [
                    NotificationCenterDetailItem(
                        id: "day-\(section.id.timeIntervalSinceReferenceDate)",
                        kind: .dayHeader(section.id)
                    )
                ] + section.rows.map { row in
                    NotificationCenterDetailItem(
                        id: "row-\(row.id.uuidString)",
                        kind: .row(row)
                    )
                }
            }
    }

    static func detailSections(
        for rows: [NotificationCenterDetailRowSnapshot],
        calendar: Calendar
    ) -> [NotificationCenterDetailSection] {
        var rowsByDay: [Date: [NotificationCenterDetailRowSnapshot]] = [:]
        rowsByDay.reserveCapacity(rows.count)

        for row in rows {
            rowsByDay[calendar.startOfDay(for: row.createdAt), default: []].append(row)
        }

        return rowsByDay.keys.sorted(by: newestDayFirst).map { day in
            NotificationCenterDetailSection(
                id: day,
                rows: (rowsByDay[day] ?? []).sorted(by: newestDetailRowFirst)
            )
        }
    }

    private static func familyActivityGroup(
        for resourceType: MistiaFamilyNotificationResourceType?
    ) -> NotificationCenterGroupID {
        switch resourceType {
        case .transaction, .familyTransfer, .debt:
            .familyCashflow
        case .wallet, .category, .budget, .goal, .card, .bill, .due, .installment, .permission, .event, .investment, nil:
            .familyData
        }
    }

    nonisolated private static func oldestNotificationFirst(
        _ lhs: AppNotificationRecord,
        _ rhs: AppNotificationRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
    }

    nonisolated private static func newestNotificationFirst(
        _ lhs: AppNotificationRecord,
        _ rhs: AppNotificationRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
    }

    nonisolated private static func newestDetailRowFirst(
        _ lhs: NotificationCenterDetailRowSnapshot,
        _ rhs: NotificationCenterDetailRowSnapshot
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
    }

    nonisolated private static func newestDayFirst(_ lhs: Date, _ rhs: Date) -> Bool {
        lhs > rhs
    }
}

private struct NotificationCenterRenderSnapshot {
    let visibleRows: [AppNotificationRecord]
    let rowByID: [UUID: AppNotificationRecord]
    let groupSummaries: [NotificationCenterGroupSummary]
    let resourceIndex: NotificationCenterResourceIndex
    let metadataIndex: NotificationCenterMetadataIndex
}

struct NotificationCenterGroupRoute: Identifiable {
    let id: NotificationCenterGroupID
    let title: String
    let unreadRowIDs: [UUID]
    let detailSections: [NotificationCenterDetailSection]
    let resourceIndex: NotificationCenterResourceIndex

    init(
        id: NotificationCenterGroupID,
        title: String,
        unreadRowIDs: [UUID],
        detailSections: [NotificationCenterDetailSection],
        resourceIndex: NotificationCenterResourceIndex
    ) {
        self.id = id
        self.title = title
        self.unreadRowIDs = unreadRowIDs
        self.detailSections = detailSections
        self.resourceIndex = resourceIndex
    }
}

extension NotificationCenterGroupRoute: Hashable {
    static func == (
        lhs: NotificationCenterGroupRoute,
        rhs: NotificationCenterGroupRoute
    ) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct NotificationCenterView: View {
    private static let groupReadDelayNanoseconds: UInt64 = 350_000_000

    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState

    @AppStorage(MistiaAppStorageKey.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(MistiaAppStorageKey.notificationsGroupFamilyEnabled) private var familyEnabled = false
    
    @Query(sort: \AppNotificationRecord.createdAt, order: .reverse)
    private var rows: [AppNotificationRecord]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil && !$0.isArchived })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil && !$0.isArchived })
    private var storedBills: [RecurringBillPlan]
    @Query private var ownershipScopes: [OwnedRecordScope]

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
    @State private var responseAlert: NotificationPermissionResponseAlert?
    @State private var selectedGroupRoute: NotificationCenterGroupRoute?
    @State private var pendingGroupDetailSnapshotRefresh = false
    @State private var renderSnapshotCache: NotificationCenterRenderSnapshot?
    @State private var isVisible = false

    private var visibleRows: [AppNotificationRecord] {
        MistiaNotificationStore.visibleRows(
            rows,
            userID: sessionStore.activeLocalProfileUserID
        )
    }

    private func makeRenderSnapshot() -> NotificationCenterRenderSnapshot {
        let visibleRows = self.visibleRows
        var rowByID: [UUID: AppNotificationRecord] = [:]
        rowByID.reserveCapacity(visibleRows.count)
        for row in visibleRows {
            rowByID[row.id] = row
        }

        return NotificationCenterRenderSnapshot(
            visibleRows: visibleRows,
            rowByID: rowByID,
            groupSummaries: NotificationCenterGrouping.summaries(for: visibleRows),
            resourceIndex: NotificationCenterResourceIndex(
                wallets: storedWallets,
                categories: storedCategories,
                bills: storedBills
            ),
            metadataIndex: NotificationCenterMetadataIndex(rows: visibleRows)
        )
    }

    var body: some View {
        let snapshot = renderSnapshotCache ?? makeRenderSnapshot()

        screen(snapshot)
        .task {
            try? MistiaNotificationDebugFixtures.seedNotificationGroupsIfNeeded(
                modelContext: modelContext,
                sessionStore: sessionStore
            )
            refreshRenderSnapshotCache()
            await refreshInbox(triggeredByPull: false)
        }
        .onChange(of: familyEnabled) { _, _ in refreshRenderSnapshotCache() }
        .onChange(of: sessionStore.activeLocalProfileUserID) { _, _ in refreshRenderSnapshotCache() }
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
        .alert(item: $responseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.common.ok))
            )
        }
        .onAppear {
            isVisible = true
            uiState.requestQuickCreateHidden(true, id: viewID)
        }
        .onDisappear {
            isVisible = false
            if selectedGroupRoute == nil {
                uiState.requestQuickCreateHidden(false, id: viewID)
            }
        }
        .background {
            NotificationGroupNativePushPresenter(
                route: $selectedGroupRoute,
                calendar: calendar,
                uiState: uiState,
                onMarkGroupAsRead: { rowIDs in
                    await markGroupAsReadAfterOpening(rowIDs)
                },
                onRowTap: { rowID, resourceIndex in
                    handleRowTap(rowID: rowID, resourceIndex: resourceIndex)
                },
                onRespond: { rowID, approve in
                    await respond(to: rowID, approve: approve)
                },
                onDismiss: {
                    handleGroupDetailDisappear()
                }
            )
            .frame(width: 0, height: 0)
        }
    }

    private func screen(_ snapshot: NotificationCenterRenderSnapshot) -> some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                groupList(
                    groups: snapshot.groupSummaries,
                    resourceIndex: snapshot.resourceIndex,
                    metadataIndex: snapshot.metadataIndex
                )
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
            .refreshable {
                await refreshInbox(triggeredByPull: true)
            }
        }
        .navigationTitle(L10n.notifications.notificationcenter.notifications)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                notificationActionsMenu
            }
        }
    }

    @MainActor
    private func refreshRenderSnapshotCache() {
        renderSnapshotCache = makeRenderSnapshot()
    }

    private var notificationActionsMenu: some View {
        Menu {
            Button {
                markAllAsRead()
            } label: {
                Label(
                    L10n.notifications.notificationcenter.markAllAsRead,
                    systemImage: "envelope.open"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L10n.notifications.notificationcenter.notificationActions)
    }

    private func groupList(
        groups: [NotificationCenterGroupSummary],
        resourceIndex: NotificationCenterResourceIndex,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> some View {
        Group {
            if groups.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        groupRow(group, metadataIndex: metadataIndex)
                            .onTapGesture {
                                selectedGroupRoute = makeRoute(
                                    for: group,
                                    resourceIndex: resourceIndex,
                                    metadataIndex: metadataIndex
                                )
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)

                        if index < groups.count - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
            }
        }
    }

    private func groupRow(
        _ group: NotificationCenterGroupSummary,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> some View {
        HStack(spacing: 14) {
            Image(group.id.fluentAssetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 34, height: 34)
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(group.id.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(groupTitleColor)
                    .lineLimit(1)

                Text(notificationTitle(for: group.latestRow, metadataIndex: metadataIndex))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(groupDetailColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            groupAccessory(group)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func groupAccessory(_ group: NotificationCenterGroupSummary) -> some View {
        if group.unreadCount > 0 {
            Text(badgeText(for: group.unreadCount))
                .font(.system(size: group.unreadCount > 99 ? 9 : 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, group.unreadCount > 9 ? 6 : 0)
                .frame(minWidth: 22, minHeight: 22)
                .background(MistiaAccent.expense.color, in: Capsule())
        } else {
            Text(MistiaDateFormatting.relativeTimeLabel(for: group.latestRow.createdAt))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func badgeText(for unreadCount: Int) -> String {
        unreadCount > 99 ? "99+" : "\(unreadCount)"
    }
    
    private var emptyState: some View {
        MistiaEmptyStateContent(
            title: L10n.notifications.notificationcenter.noNotificationsYet,
            message: L10n.notifications.notificationcenter.permissionRequestsAndFamilyActivityWillAppear,
            buttonTitle: nil,
            accent: MistiaAccent.purple.color,
            symbols: ["bell.slash.fill", "bell.badge", "envelope.badge"]
        )
    }
    
    @ViewBuilder
    private func notificationRow(
        _ row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .bottom) {
                notificationIcon(row, resourceIndex: resourceIndex)
                    .frame(width: 32, height: 32)
                    .padding(.bottom, 8)

                unreadDot(for: row)
            }
            .frame(width: 32, height: 42)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(notificationTitle(for: row, metadataIndex: metadataIndex))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(MistiaDateFormatting.relativeTimeLabel(for: row.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(notificationBody(
                    for: row,
                    resourceIndex: resourceIndex,
                    metadataIndex: metadataIndex
                ))
                    .font(.system(size: 14, weight: row.isRead ? .regular : .medium, design: .rounded))
                    .foregroundStyle(row.isRead ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                if row.opensTopUpTransfer {
                    topUpActionRow(for: row, resourceIndex: resourceIndex)
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
                            Task { @MainActor in
                                responseAlert = await respond(to: row, approve: true)
                            }
                        } label: {
                            Label(
                                L10n.notifications.notificationcenter.approve,
                                systemImage: "checkmark.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(notificationPurpleAccent)

                        Button(role: .destructive) {
                            Task { @MainActor in
                                responseAlert = await respond(to: row, approve: false)
                            }
                        } label: {
                            Label(
                                L10n.notifications.notificationcenter.reject,
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
    private func notificationIcon(
        _ row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex
    ) -> some View {
        if let bill = billPlan(for: row, resourceIndex: resourceIndex) {
            let iconSymbolName = bill.category?.iconSymbolName ?? bill.iconSymbolName
            let iconColorHex = bill.category?.iconColorHex ?? MistiaFinanceIconRegistry.defaultColorHex(for: iconSymbolName)
            MistiaFinanceIconView(
                icon: iconSymbolName,
                fallbackColor: Color(hex: iconColorHex),
                size: 32
            )
        } else if let category = categoryResource(for: row, resourceIndex: resourceIndex) {
            MistiaFinanceIconView(
                icon: category.iconSymbolName,
                fallbackColor: Color(hex: category.iconColorHex),
                size: 32
            )
        } else if let wallet = walletResource(for: row, resourceIndex: resourceIndex) {
            MistiaFinanceIconView(
                icon: wallet.iconSymbolName,
                fallbackColor: Color(hex: wallet.iconColorHex),
                size: 32
            )
        } else {
            let config = iconConfig(for: row)
            if let assetName = config.assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: config.systemImage ?? "bell.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(config.color)
            }
        }
    }

    private func topUpActionRow(
        for row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex
    ) -> some View {
        Button {
            handleRowTap(row, resourceIndex: resourceIndex)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 12, weight: .bold))

                Text(
                    L10n.notifications.notificationcenter.tapToAddFundsToWallet
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
            return IconConfig(assetName: "ic_fluent_calendar_clock_24_color", color: .orange)
        case .budgetWarning:
            return IconConfig(assetName: "ic_fluent_data_pie_24_color", color: .mint)
        case .creditCardStatementReady:
            return IconConfig(assetName: "ic_fluent_document_text_24_color", color: notificationPurpleAccent)
        case .creditCardAutoPaymentFailed, .billAutoPaymentFailed:
            return IconConfig(assetName: "ic_fluent_document_lock_24_color", color: .red)
        case .creditCardAutoPaymentSucceeded, .billAutoPaymentSucceeded:
            return IconConfig(systemImage: "checkmark.circle.fill", color: .green)
        case .lowWallet:
            return IconConfig(assetName: "ic_fluent_savings_24_color", color: .orange)
        case .permissionRequestReceived, .familyTransactionRequestReceived:
            return IconConfig(assetName: "ic_fluent_shield_checkmark_24_color", color: notificationPurpleAccent)
        case .permissionRequestApproved,
             .familyTransactionRequestApproved:
            return IconConfig(assetName: "ic_fluent_checkmark_circle_24_color", color: .green)
        case .permissionRequestRejected,
             .familyTransactionRequestRejected:
            return IconConfig(assetName: "ic_fluent_document_lock_24_color", color: .red)
        case .permissionRevoked,
             .permissionPolicyChanged:
            return IconConfig(assetName: "ic_fluent_lock_shield_24_color", color: notificationPurpleAccent)
        case .familyActivity:
            return IconConfig(assetName: "ic_fluent_people_sync_24_color", color: .blue)
        case .accessIssue:
            return IconConfig(assetName: "ic_fluent_lock_shield_24_color", color: .red)
        case .familyPlaceholder:
            return IconConfig(assetName: "ic_fluent_megaphone_loud_24_color", color: .secondary)
        }
    }

    private func makeDetailRow(
        for row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> NotificationCenterDetailRowSnapshot {
        NotificationCenterDetailRowSnapshot(
            id: row.id,
            key: row.key,
            createdAt: row.createdAt,
            title: notificationTitle(for: row, metadataIndex: metadataIndex),
            body: notificationBody(for: row, resourceIndex: resourceIndex, metadataIndex: metadataIndex),
            icon: makeIcon(for: row, resourceIndex: resourceIndex),
            action: makeAction(for: row)
        )
    }

    private func makeIcon(
        for row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex
    ) -> NotificationCenterIconSnapshot {
        if let bill = billPlan(for: row, resourceIndex: resourceIndex) {
            let iconSymbolName = bill.category?.iconSymbolName ?? bill.iconSymbolName
            let iconColorHex = bill.category?.iconColorHex ?? MistiaFinanceIconRegistry.defaultColorHex(for: iconSymbolName)
            return .finance(icon: iconSymbolName, colorHex: iconColorHex)
        }

        if let category = categoryResource(for: row, resourceIndex: resourceIndex) {
            return .finance(icon: category.iconSymbolName, colorHex: category.iconColorHex)
        }

        if let wallet = walletResource(for: row, resourceIndex: resourceIndex) {
            return .finance(icon: wallet.iconSymbolName, colorHex: wallet.iconColorHex)
        }

        let config = iconConfig(for: row)
        if let assetName = config.assetName {
            return .asset(name: assetName, color: config.color)
        }
        return .symbol(systemImage: config.systemImage ?? "bell.fill", color: config.color)
    }

    private func makeAction(for row: AppNotificationRecord) -> NotificationCenterDetailAction? {
        if row.isRespondableFamilyRequest {
            return .permissionResponse
        }

        if row.opensTopUpTransfer {
            return .primary(
                title: L10n.notifications.notificationcenter.tapToAddFundsToWallet,
                systemImage: "arrow.down.to.line.compact"
            )
        }

        if let actionHint = actionHint(for: row) {
            return .primary(
                title: actionHint,
                systemImage: row.opensCreditCardStatement ? "doc.text.fill" : "checkmark.circle.fill"
            )
        }

        return nil
    }

    private func rowRecord(for id: UUID) -> AppNotificationRecord? {
        if let row = renderSnapshotCache?.rowByID[id] {
            return row
        }
        return rows.first { $0.id == id }
    }

    private func handleRowTap(
        rowID: UUID,
        resourceIndex: NotificationCenterResourceIndex
    ) {
        guard let row = rowRecord(for: rowID) else {
            return
        }
        handleRowTap(row, resourceIndex: resourceIndex)
    }

    private func handleRowTap(
        _ row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex
    ) {
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
                name: payload.billName,
                ownerUserID: dueOwnerUserID(for: payload)
            )
        } else if row.opensCreditCardStatement, row.resourceType == .card {
            if let wallet = resourceIndex.wallet(id: row.resourceID, resourceType: row.resourceType) {
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

    private func makeRoute(
        for group: NotificationCenterGroupSummary,
        resourceIndex: NotificationCenterResourceIndex,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> NotificationCenterGroupRoute {
        let unreadRowIDs = group.rows
            .filter { !$0.isRead || $0.readAt == nil }
            .map(\.id)
        let detailRows = group.rows.map { row in
            makeDetailRow(
                for: row,
                resourceIndex: resourceIndex,
                metadataIndex: metadataIndex
            )
        }
        let detailSections = NotificationCenterGrouping.detailSections(
            for: detailRows,
            calendar: calendar
        )

        return NotificationCenterGroupRoute(
            id: group.id,
            title: group.id.title,
            unreadRowIDs: unreadRowIDs,
            detailSections: detailSections,
            resourceIndex: resourceIndex
        )
    }

    @MainActor
    private func markGroupAsReadAfterOpening(_ rowIDs: [UUID]) async {
        try? await Task.sleep(nanoseconds: Self.groupReadDelayNanoseconds)

        let unreadRows = rowIDs
            .compactMap(rowRecord(for:))
            .filter { !$0.isRead || $0.readAt == nil }
        guard !unreadRows.isEmpty else { return }

        guard let remoteIDs = try? MistiaNotificationStore.markAsRead(
            unreadRows,
            in: modelContext,
            updatesBadgeCount: false
        ) else {
            return
        }

        MistiaNotificationStore.updateAppBadgeCount(
            in: modelContext,
            userID: sessionStore.activeLocalProfileUserID
        )
        if !remoteIDs.isEmpty {
            pushNotificationReadState()
        }
        if selectedGroupRoute == nil {
            refreshRenderSnapshotCache()
        } else {
            pendingGroupDetailSnapshotRefresh = true
        }
    }

    @MainActor
    private func handleGroupDetailDisappear() {
        if !isVisible {
            uiState.requestQuickCreateHidden(false, id: viewID)
        }
        guard pendingGroupDetailSnapshotRefresh else {
            return
        }
        pendingGroupDetailSnapshotRefresh = false
        refreshRenderSnapshotCache()
    }

    private func dueOwnerUserID(for payload: DueNotificationActionPayload) -> UUID? {
        let sourceKind = PlanningDueSourceKind(rawValue: payload.sourceKind) ?? .recurringBill
        let entity: MistiaSyncEntity
        switch sourceKind {
        case .recurringBill:
            entity = .recurringBillPlan
        case .installment:
            entity = .installmentPlan
        case .creditCard:
            entity = .wallet
        }

        return MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: entity)[payload.sourceID]
            ?? familyContextStore.selectedSubjectUserID
            ?? sessionStore.activeLocalProfileUserID
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
        case .transaction, .event:
            return .transactions
        case .wallet, .category:
            return .settings
        case .budget, .goal, .card, .debt, .bill, .due, .installment, .familyTransfer:
            return .planning
        case .investment, .permission, nil:
            return .settings
        }
    }

    private func markAsRead(_ row: AppNotificationRecord) {
        markAsRead([row])
    }

    @discardableResult
    private func markAsRead(
        _ rows: [AppNotificationRecord],
        updatesBadgeCount: Bool = true,
        pushesRemoteReadState: Bool = true
    ) -> Bool {
        let unreadRows = rows.filter { !$0.isRead || $0.readAt == nil }
        guard !unreadRows.isEmpty,
              let remoteIDs = try? MistiaNotificationStore.markAsRead(
                unreadRows,
                in: modelContext,
                updatesBadgeCount: updatesBadgeCount
              ) else {
            return false
        }
        refreshRenderSnapshotCache()
        guard !remoteIDs.isEmpty else {
            return false
        }
        if pushesRemoteReadState {
            pushNotificationReadState()
        }
        return true
    }

    private func pushNotificationReadState() {
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

    @MainActor
    private func respond(to rowID: UUID, approve: Bool) async -> NotificationPermissionResponseAlert {
        guard let row = rowRecord(for: rowID) else {
            return .failure(
                message: L10n.notifications.notificationcenter.mistiaCouldnTSendThisResponseYet
            )
        }
        return await respond(to: row, approve: approve)
    }

    @MainActor
    private func respond(to row: AppNotificationRecord, approve: Bool) async -> NotificationPermissionResponseAlert {
        let snapshot = NotificationResponseSnapshot(row: row)
        applyImmediatePermissionResponse(to: row, approve: approve)

        let didRespond = await familyContextStore.respondToPermissionNotification(
            row,
            approve: approve,
            sessionStore: sessionStore
        )
        guard didRespond else {
            snapshot.restore(row)
            try? modelContext.save()
            refreshRenderSnapshotCache()
            return .failure(
                message: familyContextStore.lastErrorMessage
                    ?? L10n.notifications.notificationcenter.mistiaCouldnTSendThisResponseYet
            )
        }

        refreshRenderSnapshotCache()
        pendingGroupDetailSnapshotRefresh = true
        return .success(approve: approve)
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

    private func notificationTitle(
        for row: AppNotificationRecord,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> String {
        switch row.kind {
        case .permissionRequestReceived, .familyTransactionRequestReceived:
            if row.actionState == .approved {
                return resolvedPermissionRequestTitle(for: row, approve: true)
            } else if row.actionState == .rejected {
                return resolvedPermissionRequestTitle(for: row, approve: false)
            }
            return pendingPermissionRequestTitle(for: row)
            
        case .permissionRequestApproved, .familyTransactionRequestApproved:
            let resource = row.resourceType?.localizedName ?? L10n.notifications.notificationcenter.access
            let scope = row.permissionScope?.localizedActionName ?? ""
            let action = L10n.notifications.notificationcenter.approved3
            
            if !scope.isEmpty {
                return L10n.notifications.notificationcenter.valueValueRequestValue(String(describing: scope), String(describing: resource), String(describing: action))
            }
            return L10n.notifications.notificationcenter.valueRequestValue(String(describing: resource), String(describing: action))
            
        case .permissionRequestRejected, .familyTransactionRequestRejected:
            let resource = row.resourceType?.localizedName ?? L10n.notifications.notificationcenter.access
            let scope = row.permissionScope?.localizedActionName ?? ""
            let action = L10n.notifications.notificationcenter.rejected3
            
            if !scope.isEmpty {
                return L10n.notifications.notificationcenter.valueValueRequestValue(String(describing: scope), String(describing: resource), String(describing: action))
            }
            return L10n.notifications.notificationcenter.valueRequestValue(String(describing: resource), String(describing: action))
            
        case .permissionRevoked:
            let resource = row.resourceType?.localizedName ?? L10n.notifications.notificationcenter.access
            return L10n.notifications.notificationcenter.revokedValueAccess(String(describing: resource))
            
        case .familyActivity:
            if let metadata = metadataIndex.stringMetadata(for: row) {
                return NotificationCenterDisplayText.familyActivityTitle(
                    resourceType: row.resourceType,
                    actionRaw: metadata["action"],
                    isMemberJoin: isMemberJoinNotification(metadata),
                    fallbackTitle: row.title
                )
            }
            return row.title

        default:
            return row.title
        }
    }

    private func notificationBody(
        for row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> String {
        switch row.kind {
        case .permissionRequestReceived, .familyTransactionRequestReceived:
            if row.actionState == .approved {
                return resolvedPermissionRequestBody(approve: true)
            } else if row.actionState == .rejected {
                return resolvedPermissionRequestBody(approve: false)
            }
            return pendingPermissionRequestBody(
                for: row,
                resourceIndex: resourceIndex,
                metadataIndex: metadataIndex
            )
            
        case .permissionRequestApproved, .permissionRequestRejected,
             .familyTransactionRequestApproved, .familyTransactionRequestRejected:
            let actorName = familyContextStore.displayName(for: row.actorUserID)
                ?? L10n.notifications.notificationcenter.member
            
            let isApproved = row.kind == .permissionRequestApproved || row.kind == .familyTransactionRequestApproved
            let action = isApproved
                ? L10n.notifications.notificationcenter.approved2
                : L10n.notifications.notificationcenter.rejected2
            
            let scope = row.permissionScope?.localizedActionName ?? ""
            let resourceType = row.resourceType?.localizedName ?? ""
            let resourceName = resolvedResourceName(
                for: row,
                resourceIndex: resourceIndex,
                metadataIndex: metadataIndex
            ) ?? ""
            let resourceDetail = resourceName.isEmpty ? resourceType : "\(resourceType) (\(resourceName))"
            
            if !scope.isEmpty {
                return L10n.notifications.notificationcenter.valueValueYourValueValueRequest(String(describing: actorName), String(describing: action), String(describing: scope), String(describing: resourceDetail))
            }
            return L10n.notifications.notificationcenter.valueValueYourValueRequest(String(describing: actorName), String(describing: action), String(describing: resourceDetail))
            
        case .permissionRevoked:
            let actorName = familyContextStore.displayName(for: row.actorUserID)
                ?? L10n.notifications.notificationcenter.theOwner
            let resourceType = row.resourceType?.localizedName ?? ""
            if let resourceName = resolvedResourceName(
                for: row,
                resourceIndex: resourceIndex,
                metadataIndex: metadataIndex
            ) {
                return L10n.notifications.notificationcenter.valueRevokedYourAccessToValueValue(String(describing: actorName), String(describing: resourceType), String(describing: resourceName))
            }
            return row.body
            
        case .familyActivity:
            let actorName = familyContextStore.displayName(for: row.actorUserID)
                ?? L10n.notifications.notificationcenter.aMember
            
            if let metadata = metadataIndex.stringMetadata(for: row) {
                if isMemberJoinNotification(metadata) {
                    return NotificationCenterDisplayText.memberJoinedBody(
                        actorName: actorName,
                        fallbackBody: row.body
                    )
                }
                
                if let actionRaw = metadata["action"] {
                    if actionRaw == "family_transfer" {
                        return NotificationCenterDisplayText.familyTransferReceivedBody(
                            actorName: actorName,
                            walletName: familyTransferDestinationWalletName(
                                metadata: metadata,
                                resourceIndex: resourceIndex
                            ),
                            amountText: familyTransferAmountText(metadata: metadata),
                            fallbackBody: row.body
                        )
                    }

                    let actionLabel: String
                    switch actionRaw {
                    case "created": actionLabel = L10n.notifications.notificationcenter.created
                    case "updated": actionLabel = L10n.notifications.notificationcenter.updated
                    case "deleted": actionLabel = L10n.notifications.notificationcenter.deleted
                    default: actionLabel = L10n.notifications.notificationcenter.changed
                    }
                    
                    let resourceType = row.resourceType?.localizedName ?? ""
                    let resourceName = resolvedResourceName(
                        for: row,
                        resourceIndex: resourceIndex,
                        metadataIndex: metadataIndex
                    ) ?? ""
                    let resourceDetail = resourceName.isEmpty ? resourceType : "\(resourceType) (\(resourceName))"
                    
                    if let amountMinorStr = metadata["amount_minor"],
                       let amountMinor = Int64(amountMinorStr),
                       let currencyCode = metadata["currency_code"] {
                        let amountText = amountMinor.formattedCurrency(code: currencyCode)
                        return L10n.notifications.notificationcenter.valueValueValueWorthValue(String(describing: actorName), String(describing: actionLabel), String(describing: resourceDetail), String(describing: amountText))
                    }
                    
                    return L10n.notifications.notificationcenter.valueValueYourValue(String(describing: actorName), String(describing: actionLabel), String(describing: resourceDetail))
                }
            }
            return row.body

        default:
            return row.body
        }
    }

    private func resolvedResourceName(
        for row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> String? {
        if let wallet = walletResource(for: row, resourceIndex: resourceIndex) {
            return wallet.name
        }
        if let category = categoryResource(for: row, resourceIndex: resourceIndex) {
            return category.name
        }
        if let bill = billPlan(for: row, resourceIndex: resourceIndex) {
            return bill.name
        }
        
        if let metadata = metadataIndex.objectMetadata(for: row) {
            return metadata["wallet_name"] as? String
                ?? metadata["category_name"] as? String
                ?? metadata["bill_name"] as? String
                ?? metadata["transaction_title"] as? String
                ?? metadata["goal_name"] as? String
                ?? metadata["installment_name"] as? String
        }
        
        return nil
    }

    private func pendingPermissionRequestTitle(for row: AppNotificationRecord) -> String {
        let resource = row.resourceType?.localizedName ?? L10n.notifications.notificationcenter.access
        let scope = row.permissionScope?.localizedActionName ?? ""

        if !scope.isEmpty {
            return L10n.shared.family.familycontext.requestToValueValue(
                String(describing: scope),
                String(describing: resource)
            )
        }

        return row.title
    }

    private func pendingPermissionRequestBody(
        for row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> String {
        let scope = row.permissionScope?.localizedActionName ?? ""
        guard !scope.isEmpty else {
            return row.body
        }

        let requesterName = permissionRequesterName(for: row)
        let resourceName = resolvedResourceName(
            for: row,
            resourceIndex: resourceIndex,
            metadataIndex: metadataIndex
        ) ?? row.resourceType?.localizedName
            ?? L10n.notifications.notificationcenter.access

        return L10n.shared.family.familycontext.valueWantsToValueYourValue(
            String(describing: requesterName),
            String(describing: scope),
            String(describing: resourceName)
        )
    }

    private func resolvedPermissionRequestTitle(for row: AppNotificationRecord, approve: Bool) -> String {
        let name = permissionRequesterName(for: row)
        let action = approve
            ? L10n.notifications.notificationcenter.approved
            : L10n.notifications.notificationcenter.rejected
        let resource = row.resourceType?.localizedName ?? L10n.notifications.notificationcenter.access
        let scope = row.permissionScope?.localizedActionName ?? ""
        
        if !scope.isEmpty {
            return L10n.notifications.notificationcenter.valueValueSValueValueRequest(String(describing: action), String(describing: scope), String(describing: resource), String(describing: name))
        }
        
        return L10n.notifications.notificationcenter.valueValueSValueRequest(String(describing: action), String(describing: resource), String(describing: name))
    }

    private func resolvedPermissionRequestBody(approve: Bool) -> String {
        NotificationCenterDisplayText.permissionResponseBody(approve: approve)
    }

    private func permissionRequesterName(for row: AppNotificationRecord) -> String {
        familyContextStore.displayName(for: row.actorUserID)
            ?? L10n.notifications.notificationcenter.thisMember
    }

    private func familyTransferDestinationWalletName(
        metadata: [String: String],
        resourceIndex: NotificationCenterResourceIndex
    ) -> String? {
        guard let walletID = metadata["destination_wallet_id"].flatMap(UUID.init(uuidString:)) else {
            return nil
        }

        return resourceIndex.wallet(id: walletID)?.name
    }

    private func familyTransferAmountText(metadata: [String: String]) -> String? {
        let amountMinorText = metadata["destination_amount_minor"] ?? metadata["amount_minor"]
        let currencyCode = metadata["destination_currency_code"]
            ?? metadata["currency_code"]
            ?? metadata["source_currency_code"]
        guard let amountMinorText,
              let amountMinor = Int64(amountMinorText),
              let currencyCode else {
            return nil
        }

        return amountMinor.formattedCurrency(code: currencyCode)
    }

    private func isMemberJoinNotification(_ metadata: [String: String]) -> Bool {
        metadata["joined_user_id"] != nil
            || metadata["invite_id"] != nil
            || metadata["member_user_id"] != nil
    }

    private func actionHint(for row: AppNotificationRecord) -> String? {
        if row.opensCreditCardStatement {
            return L10n.notifications.notificationcenter.tapToOpenTheStatementAndPay
        }

        if row.opensDuePaymentSheet {
            return L10n.notifications.notificationcenter.tapToPay
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
            familyContextStore: familyContextStore,
            referenceDate: .now,
            calendar: calendar
        )
        await familyContextStore.refreshNotifications(sessionStore: sessionStore)
        refreshRenderSnapshotCache()
    }

    private var notificationPurpleAccent: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    private var groupTitleColor: Color {
        colorScheme == .dark ? .primary.opacity(0.96) : .primary
    }

    private var groupDetailColor: Color {
        colorScheme == .dark ? .primary.opacity(0.72) : .secondary
    }

    private func billPlan(
        for row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex
    ) -> RecurringBillPlan? {
        resourceIndex.bill(id: row.resourceID, resourceType: row.resourceType)
    }

    private func categoryResource(
        for row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex
    ) -> TransactionCategory? {
        resourceIndex.category(id: row.resourceID, resourceType: row.resourceType)
    }

    private func walletResource(
        for row: AppNotificationRecord,
        resourceIndex: NotificationCenterResourceIndex
    ) -> LedgerWallet? {
        resourceIndex.wallet(id: row.resourceID, resourceType: row.resourceType)
    }
}

private enum MistiaNotificationDebugFixtures {
    static func seedNotificationGroupsIfNeeded(
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) throws {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["MISTIA_NOTIFICATION_DEBUG_SAMPLE_DATA"] == "1" else {
            return
        }

        let requestedCount = Int(ProcessInfo.processInfo.environment["MISTIA_NOTIFICATION_DEBUG_SAMPLE_COUNT"] ?? "") ?? 1_500
        let sampleCount = max(32, min(requestedCount, 5_000))
        let existingKeys = Set(
            try modelContext.fetch(FetchDescriptor<AppNotificationRecord>())
                .map(\.key)
                .filter { $0.hasPrefix("debug.notification.group.") }
        )
        guard existingKeys.isEmpty else {
            return
        }

        let now = Date()
        let calendar = MistiaCalendar.current
        let recipientUserID = sessionStore.activeLocalProfileUserID
        let groupSeeds: [(kind: MistiaAppNotificationKind, resourceType: MistiaFamilyNotificationResourceType?, title: String)] = [
            (.creditCardStatementReady, .card, "Debug card statement"),
            (.billPaymentRequired, .bill, "Debug bill payment"),
            (.budgetWarning, .budget, "Debug budget warning"),
            (.lowWallet, .wallet, "Debug low wallet"),
            (.familyActivity, .transaction, "Debug family transaction"),
            (.permissionRequestReceived, .permission, "Debug permission request"),
            (.familyPlaceholder, nil, "Debug family data"),
            (.creditCardAutoPaymentFailed, .card, "Debug card payment failed")
        ]

        for index in 0..<sampleCount {
            let seed = groupSeeds[index % groupSeeds.count]
            let createdAt = calendar.date(
                byAdding: .minute,
                value: -index,
                to: now
            ) ?? now
            let actionState: MistiaNotificationActionState? = seed.kind == .permissionRequestReceived
                ? .pending
                : .informational

            modelContext.insert(AppNotificationRecord(
                key: "debug.notification.group.\(index)",
                createdAt: createdAt,
                updatedAt: createdAt,
                title: "\(seed.title) \(index)",
                body: "Debug notification body \(index)",
                kind: seed.kind,
                source: .system,
                isRead: index % 4 == 0,
                recipientUserID: recipientUserID,
                resourceType: seed.resourceType,
                resourceID: UUID(),
                permissionScope: seed.kind == .permissionRequestReceived ? .edit : nil,
                permissionRequestID: seed.kind == .permissionRequestReceived ? UUID() : nil,
                actionState: actionState,
                metadataJSON: "{\"actorName\":\"Debug User\",\"resourceName\":\"Debug Resource \(index)\",\"amountText\":\"¥\(index + 1)\"}"
            ))
        }

        try modelContext.save()
        MistiaNotificationStore.updateAppBadgeCount(in: modelContext, userID: recipientUserID)
        #endif
    }
}

struct MistiaNotificationBellLink: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Query(filter: #Predicate<AppNotificationRecord> { !$0.isRead })
    private var rows: [AppNotificationRecord]

    private var unreadCount: Int {
        MistiaNotificationStore.unreadCount(
            rows: rows,
            userID: sessionStore.activeLocalProfileUserID
        )
    }

    var body: some View {
        let unreadCount = unreadCount

        Group {
            if #available(iOS 26.0, *) {
                NavigationLink {
                    NotificationCenterView()
                } label: {
                    MistiaCircleGlassButtonLabel {
                        bellContent(unreadCount: unreadCount)
                    }
                }
                .buttonStyle(.glass(nativeGlassStyle))
                .buttonBorderShape(.circle)
            } else {
                NavigationLink {
                    NotificationCenterView()
                } label: {
                    MistiaCircleGlassButtonLabel {
                        bellContent(unreadCount: unreadCount)
                    }
                    .background {
                        MistiaCircleGlassBackground(
                            tint: colorScheme == .dark ? .white.opacity(0.12) : .white.opacity(0.30),
                            interactive: true
                        )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .hoverEffect(.highlight)
        .accessibilityLabel(accessibilityLabel(unreadCount: unreadCount))
    }

    private func badgeText(for unreadCount: Int) -> String {
        unreadCount > 99 ? "99+" : "\(unreadCount)"
    }

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        Glass.regular
            .interactive()
    }

    private func accessibilityLabel(unreadCount: Int) -> String {
        guard unreadCount > 0 else {
            return L10n.notifications.notificationcenter.notifications
        }
        return L10n.notifications.notificationcenter.valueUnreadNotifications(String(describing: unreadCount))
    }

    private func bellContent(unreadCount: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell")
                .font(.system(size: 17, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)

            if unreadCount > 0 {
                Text(badgeText(for: unreadCount))
                    .font(.system(size: unreadCount > 99 ? 7 : 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, unreadCount > 9 ? 3 : 0)
                    .frame(minWidth: 13, minHeight: 13)
                    .background(MistiaAccent.expense.color, in: Capsule())
                    .offset(x: 9, y: -9)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct NotificationGroupNativePushPresenter: UIViewControllerRepresentable {
    @Binding var route: NotificationCenterGroupRoute?

    let calendar: Calendar
    let uiState: MistiaUIState
    let onMarkGroupAsRead: ([UUID]) async -> Void
    let onRowTap: (UUID, NotificationCenterResourceIndex) -> Void
    let onRespond: (UUID, Bool) async -> NotificationPermissionResponseAlert
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PresenterViewController {
        PresenterViewController()
    }

    func updateUIViewController(_ uiViewController: PresenterViewController, context: Context) {
        uiViewController.update(
            route: route,
            calendar: calendar,
            uiState: uiState,
            onMarkGroupAsRead: onMarkGroupAsRead,
            onRowTap: onRowTap,
            onRespond: onRespond,
            onDismiss: {
                route = nil
                onDismiss()
            }
        )
    }

    final class PresenterViewController: UIViewController {
        private var presentedRouteID: NotificationCenterGroupID?

        func update(
            route: NotificationCenterGroupRoute?,
            calendar: Calendar,
            uiState: MistiaUIState,
            onMarkGroupAsRead: @escaping ([UUID]) async -> Void,
            onRowTap: @escaping (UUID, NotificationCenterResourceIndex) -> Void,
            onRespond: @escaping (UUID, Bool) async -> NotificationPermissionResponseAlert,
            onDismiss: @escaping () -> Void
        ) {
            guard let route else {
                presentedRouteID = nil
                return
            }
            guard presentedRouteID != route.id else { return }

            presentedRouteID = route.id
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentedRouteID == route.id else { return }
                guard let navigationController = self.navigationController else { return }

                let detail = NotificationGroupDetailScreen(
                    route,
                    calendar: calendar,
                    uiState: uiState,
                    onMarkGroupAsRead: onMarkGroupAsRead,
                    onRowTap: onRowTap,
                    onRespond: onRespond,
                    onFinishResponse: { [weak navigationController] in
                        navigationController?.popViewController(animated: true)
                    }
                )
                let host = HostingController(rootView: detail, routeID: route.id) { [weak self] in
                    self?.presentedRouteID = nil
                    onDismiss()
                }
                host.title = route.title
                navigationController.pushViewController(host, animated: true)
            }
        }
    }

    final class HostingController: UIHostingController<NotificationGroupDetailScreen> {
        private let routeID: NotificationCenterGroupID
        private let onNativePop: () -> Void

        init(
            rootView: NotificationGroupDetailScreen,
            routeID: NotificationCenterGroupID,
            onNativePop: @escaping () -> Void
        ) {
            self.routeID = routeID
            self.onNativePop = onNativePop
            super.init(rootView: rootView)
        }

        @available(*, unavailable)
        @MainActor dynamic required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isMovingFromParent || navigationController?.viewControllers.contains(self) == false {
                onNativePop()
            }
        }
    }
}

struct NotificationPermissionResponseAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let dismissesDetail: Bool

    static func success(approve: Bool) -> NotificationPermissionResponseAlert {
        NotificationPermissionResponseAlert(
            title: approve
                ? L10n.notifications.notificationcenter.approved
                : L10n.notifications.notificationcenter.rejected,
            message: NotificationCenterDisplayText.permissionResponseBody(approve: approve),
            dismissesDetail: true
        )
    }

    static func failure(message: String) -> NotificationPermissionResponseAlert {
        NotificationPermissionResponseAlert(
            title: L10n.notifications.notificationcenter.couldnTRespond,
            message: message,
            dismissesDetail: false
        )
    }
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
