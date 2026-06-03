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
            "checkmark.circle.fill"
        case .access:
            "lock.fill"
        case .familyCashflow:
            "person.2.fill"
        case .familyData:
            "folder.fill"
        case .bills:
            "calendar.badge.clock"
        case .creditCards:
            "creditcard.fill"
        case .wallets:
            "tray.and.arrow.down.fill"
        case .budgets:
            "chart.pie.fill"
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
}

struct NotificationCenterGroupSummary: Identifiable {
    let id: NotificationCenterGroupID
    let rows: [AppNotificationRecord]
    let latestRow: AppNotificationRecord
    let unreadCount: Int
}

struct NotificationCenterDaySection: Identifiable {
    let id: Date
    let rows: [AppNotificationRecord]
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
        var rowsByGroup: [NotificationCenterGroupID: [AppNotificationRecord]] = [:]
        rowsByGroup.reserveCapacity(NotificationCenterGroupID.allCases.count)

        for row in rows {
            guard let groupID = groupID(for: row) else { continue }
            rowsByGroup[groupID, default: []].append(row)
        }

        return NotificationCenterGroupID.allCases.compactMap { groupID in
            guard let rows = rowsByGroup[groupID], !rows.isEmpty else { return nil }
            let sortedRows = rows.sorted(by: ascendingNotificationSort)
            guard let latestRow = sortedRows.last else { return nil }
            return NotificationCenterGroupSummary(
                id: groupID,
                rows: sortedRows,
                latestRow: latestRow,
                unreadCount: sortedRows.filter { !$0.isRead }.count
            )
        }
        .sorted { lhs, rhs in
            descendingNotificationSort(lhs.latestRow, rhs.latestRow)
        }
    }

    static func summary(
        for groupID: NotificationCenterGroupID,
        in rows: [AppNotificationRecord]
    ) -> NotificationCenterGroupSummary? {
        var groupRows: [AppNotificationRecord] = []
        groupRows.reserveCapacity(rows.count)

        for row in rows where self.groupID(for: row) == groupID {
            groupRows.append(row)
        }

        guard !groupRows.isEmpty else { return nil }
        let sortedRows = groupRows.sorted(by: ascendingNotificationSort)
        guard let latestRow = sortedRows.last else { return nil }

        return NotificationCenterGroupSummary(
            id: groupID,
            rows: sortedRows,
            latestRow: latestRow,
            unreadCount: sortedRows.filter { !$0.isRead }.count
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
                rows: (rowsByDay[day] ?? []).sorted(by: ascendingNotificationSort)
            )
        }
    }

    static func bottomAnchoredDetailItems(
        for rows: [NotificationCenterDetailRowSnapshot],
        calendar: Calendar
    ) -> [NotificationCenterDetailItem] {
        detailDaySections(for: rows, calendar: calendar)
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

    private static func detailDaySections(
        for rows: [NotificationCenterDetailRowSnapshot],
        calendar: Calendar
    ) -> [(id: Date, rows: [NotificationCenterDetailRowSnapshot])] {
        var rowsByDay: [Date: [NotificationCenterDetailRowSnapshot]] = [:]
        rowsByDay.reserveCapacity(rows.count)

        for row in rows {
            rowsByDay[calendar.startOfDay(for: row.createdAt), default: []].append(row)
        }

        return rowsByDay.keys.sorted().map { day in
            (
                id: day,
                rows: (rowsByDay[day] ?? []).sorted(by: ascendingDetailSort)
            )
        }
    }

    private static func familyActivityGroup(
        for resourceType: MistiaFamilyNotificationResourceType?
    ) -> NotificationCenterGroupID {
        switch resourceType {
        case .transaction, .familyTransfer, .debt:
            .familyCashflow
        case .wallet, .category, .budget, .goal, .card, .bill, .due, .installment, .permission, nil:
            .familyData
        }
    }

    nonisolated private static func ascendingNotificationSort(
        _ lhs: AppNotificationRecord,
        _ rhs: AppNotificationRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
    }

    nonisolated private static func descendingNotificationSort(
        _ lhs: AppNotificationRecord,
        _ rhs: AppNotificationRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
    }

    nonisolated private static func ascendingDetailSort(
        _ lhs: NotificationCenterDetailRowSnapshot,
        _ rhs: NotificationCenterDetailRowSnapshot
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
    }
}

private struct NotificationCenterRenderSnapshot {
    let visibleRows: [AppNotificationRecord]
    let rowByID: [UUID: AppNotificationRecord]
    let groupSummaries: [NotificationCenterGroupSummary]
    let resourceIndex: NotificationCenterResourceIndex
    let metadataIndex: NotificationCenterMetadataIndex
}

private struct NotificationCenterGroupRoute: Identifiable {
    let id: NotificationCenterGroupID
    let title: String
    let unreadRowIDs: [UUID]

    init(
        id: NotificationCenterGroupID,
        title: String,
        unreadRowIDs: [UUID]
    ) {
        self.id = id
        self.title = title
        self.unreadRowIDs = unreadRowIDs
    }
}

private struct NotificationGroupScreenEdgeBackGesture: UIViewRepresentable {
    let isEnabled: Bool
    let onBack: @MainActor () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = EdgePanHostView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        context.coordinator.update(isEnabled: isEnabled, onBack: onBack)
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(isEnabled: isEnabled, onBack: onBack)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onBack: onBack)
    }

    final class EdgePanHostView: UIView {
        private let activeWidth: CGFloat = 44

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            point.x >= 0 && point.x <= activeWidth && point.y >= 0 && point.y <= bounds.height
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var isEnabled: Bool
        private var onBack: @MainActor () -> Void
        private var gestures: [UIGestureRecognizer] = []

        init(isEnabled: Bool, onBack: @escaping @MainActor () -> Void) {
            self.isEnabled = isEnabled
            self.onBack = onBack
        }

        func update(isEnabled: Bool, onBack: @escaping @MainActor () -> Void) {
            self.isEnabled = isEnabled
            self.onBack = onBack
            gestures.forEach { $0.isEnabled = isEnabled }
        }

        func attach(to view: UIView) {
            detach()

            let edgeGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
            edgeGesture.edges = .left
            edgeGesture.cancelsTouchesInView = false
            edgeGesture.delegate = self
            edgeGesture.isEnabled = isEnabled
            view.addGestureRecognizer(edgeGesture)

            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
            panGesture.cancelsTouchesInView = false
            panGesture.delegate = self
            panGesture.isEnabled = isEnabled
            view.addGestureRecognizer(panGesture)

            gestures = [edgeGesture, panGesture]
        }

        func detach() {
            for gesture in gestures {
                gesture.view?.removeGestureRecognizer(gesture)
            }
            gestures = []
        }

        @objc private func handleEdgePan(_ gesture: UIPanGestureRecognizer) {
            guard isEnabled, gesture.state == .ended || gesture.state == .recognized else { return }
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            guard translation.x >= 28 || velocity.x >= 260 else { return }

            Task { @MainActor [onBack] in
                onBack()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled else { return false }
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = panGesture.velocity(in: gestureRecognizer.view)
            return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
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
    @State private var responseErrorAlert: NotificationResponseErrorAlert?
    @State private var selectedGroupRoute: NotificationCenterGroupRoute?
    @State private var selectedGroupDetailItems: [NotificationCenterDetailItem] = []
    @State private var selectedGroupResourceIndex = NotificationCenterResourceIndex(wallets: [], categories: [], bills: [])
    @State private var renderSnapshotCache: NotificationCenterRenderSnapshot?

    private var visibleRows: [AppNotificationRecord] {
        MistiaNotificationStore.visibleRows(
            rows,
            userID: sessionStore.activeLocalProfileUserID
        )
    }

    private var emptyRenderSnapshot: NotificationCenterRenderSnapshot {
        NotificationCenterRenderSnapshot(
            visibleRows: [],
            rowByID: [:],
            groupSummaries: [],
            resourceIndex: NotificationCenterResourceIndex(wallets: [], categories: [], bills: []),
            metadataIndex: NotificationCenterMetadataIndex(rows: [])
        )
    }

    private func makeRenderSnapshot() -> NotificationCenterRenderSnapshot {
        let visibleRows = self.visibleRows
        let rowByID = Dictionary(uniqueKeysWithValues: visibleRows.map { ($0.id, $0) })
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
        let snapshot = renderSnapshotCache ?? emptyRenderSnapshot

        Group {
            if let selectedGroupRoute {
                notificationGroupDetailScreen(
                    selectedGroupRoute,
                    detailItems: selectedGroupDetailItems,
                    resourceIndex: selectedGroupResourceIndex
                )
            } else {
                notificationGroupListScreen(snapshot)
            }
        }
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
        .alert(item: $responseErrorAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.common.ok))
            )
        }
        .onAppear {
            uiState.requestQuickCreateHidden(true, id: viewID)
        }
        .onDisappear {
            uiState.requestQuickCreateHidden(false, id: viewID)
        }
    }

    private func notificationGroupListScreen(_ snapshot: NotificationCenterRenderSnapshot) -> some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.notifications.notificationcenter.notifications,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            onRefresh: { await refreshInbox(triggeredByPull: true) },
            pinnedHeader: { EmptyView() },
            trailingAccessory: { trailingMenu },
            content: {
                content(
                    groups: snapshot.groupSummaries,
                    resourceIndex: snapshot.resourceIndex,
                    metadataIndex: snapshot.metadataIndex
                )
            }
        )
    }

    @MainActor
    private func refreshRenderSnapshotCache() {
        renderSnapshotCache = makeRenderSnapshot()
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
                    L10n.notifications.notificationcenter.markAllAsRead,
                    systemImage: "envelope.open"
                )
            }
        }
        .accessibilityLabel(L10n.notifications.notificationcenter.notificationActions)
    }

    private func content(
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
                        Button {
                            openGroup(
                                group,
                                resourceIndex: resourceIndex,
                                metadataIndex: metadataIndex
                            )
                        } label: {
                            notificationGroupRow(group, metadataIndex: metadataIndex)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: group.id.accentColor))

                        if index < groups.count - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
            }
        }
    }

    private func notificationGroupRow(
        _ group: NotificationCenterGroupSummary,
        metadataIndex: NotificationCenterMetadataIndex
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(group.id.accentColor)

                Image(systemName: group.id.systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(group.id.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(notificationTitle(for: group.latestRow, metadataIndex: metadataIndex))
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            groupTrailingAccessory(group)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func groupTrailingAccessory(_ group: NotificationCenterGroupSummary) -> some View {
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

    private func notificationGroupDetailScreen(
        _ route: NotificationCenterGroupRoute,
        detailItems: [NotificationCenterDetailItem],
        resourceIndex: NotificationCenterResourceIndex
    ) -> some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                notificationGroupDetailHeader(title: route.title)

                notificationGroupDetailList(
                    detailItems: detailItems,
                    resourceIndex: resourceIndex
                )
            }
        }
        .overlay(alignment: .leading) {
            NotificationGroupScreenEdgeBackGesture(isEnabled: selectedGroupRoute != nil) {
                closeGroupDetail()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task(id: route.id) {
            await markGroupAsReadAfterOpening(route.unreadRowIDs)
        }
    }

    private func notificationGroupDetailHeader(title: String) -> some View {
        HStack(spacing: 12) {
            MistiaHeaderCircleButton(action: closeGroupDetail) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel(L10n.notifications.notificationcenter.notifications)

            Spacer(minLength: 6)

            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 6)

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func notificationGroupDetailList(
        detailItems: [NotificationCenterDetailItem],
        resourceIndex: NotificationCenterResourceIndex
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if detailItems.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        ForEach(detailItems) { item in
                            notificationDetailItem(
                                item,
                                resourceIndex: resourceIndex
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .onAppear {
                scrollDetailToBottom(proxy, itemID: detailItems.last?.id)
            }
            .onChange(of: detailItems.last?.id) { _, itemID in
                scrollDetailToBottom(proxy, itemID: itemID)
            }
        }
    }

    private func scrollDetailToBottom(
        _ proxy: ScrollViewProxy,
        itemID: String?
    ) {
        guard let itemID else { return }
        proxy.scrollTo(itemID, anchor: .bottom)
    }

    @ViewBuilder
    private func notificationDetailItem(
        _ item: NotificationCenterDetailItem,
        resourceIndex: NotificationCenterResourceIndex
    ) -> some View {
        switch item.kind {
        case .dayHeader(let day):
            notificationDayHeader(day)
        case .row(let row):
            notificationDetailRow(
                row,
                resourceIndex: resourceIndex
            )
        }
    }

    private func notificationDayHeader(_ day: Date) -> some View {
        Text(notificationSectionTitle(for: day))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }

    private func notificationDetailRow(
        _ row: NotificationCenterDetailRowSnapshot,
        resourceIndex: NotificationCenterResourceIndex
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            notificationIcon(row.icon)
                .frame(width: 36, height: 36)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(row.title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(row.body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                notificationDetailActions(for: row, resourceIndex: resourceIndex)

                HStack {
                    Spacer(minLength: 0)

                    Text(row.createdAt, style: .time)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .background(
            Color(UIColor.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            handleRowTap(rowID: row.id, resourceIndex: resourceIndex)
        }
    }

    @ViewBuilder
    private func notificationDetailActions(
        for row: NotificationCenterDetailRowSnapshot,
        resourceIndex: NotificationCenterResourceIndex
    ) -> some View {
        switch row.action {
        case .permissionResponse:
            HStack(spacing: 8) {
                Button {
                    respond(to: row.id, approve: true)
                } label: {
                    Label(
                        L10n.notifications.notificationcenter.approve,
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(NotificationDetailActionButtonStyle(foreground: notificationPurpleAccent))

                Button(role: .destructive) {
                    respond(to: row.id, approve: false)
                } label: {
                    Label(
                        L10n.notifications.notificationcenter.reject,
                        systemImage: "xmark.circle.fill"
                    )
                }
                .buttonStyle(NotificationDetailActionButtonStyle(foreground: .red))
            }
            .padding(.top, 2)
        case .primary(let title, let systemImage):
            notificationDetailSingleActionButton(
                title: title,
                systemImage: systemImage,
                row: row,
                resourceIndex: resourceIndex
            )
        case nil:
            EmptyView()
        }
    }

    private func notificationDetailSingleActionButton(
        title: String,
        systemImage: String,
        row: NotificationCenterDetailRowSnapshot,
        resourceIndex: NotificationCenterResourceIndex
    ) -> some View {
        Button {
            handleRowTap(rowID: row.id, resourceIndex: resourceIndex)
        } label: {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .buttonStyle(NotificationDetailActionButtonStyle(foreground: notificationPurpleAccent))
        .padding(.top, 2)
    }

    private func notificationSectionTitle(for day: Date) -> String {
        let referenceDay = calendar.startOfDay(for: Date())
        let dayDelta = calendar.dateComponents([.day], from: day, to: referenceDay).day ?? 0
        return MistiaDateFormatting.relativeDayLabel(for: dayDelta)
            ?? MistiaDateFormatting.fullDateString(for: day, calendar: calendar)
    }

    private func badgeText(for unreadCount: Int) -> String {
        unreadCount > 99 ? "99+" : "\(unreadCount)"
    }
    
    private var emptyState: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.notifications.notificationcenter.noNotificationsYet)
                .font(.system(.headline, design: .rounded))

                Text(L10n.notifications.notificationcenter.permissionRequestsAndFamilyActivityWillAppear)
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
                            respond(to: row, approve: true)
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
                            respond(to: row, approve: false)
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

    @ViewBuilder
    private func notificationIcon(_ snapshot: NotificationCenterIconSnapshot) -> some View {
        switch snapshot {
        case .finance(let icon, let colorHex):
            MistiaFinanceIconView(
                icon: icon,
                fallbackColor: Color(hex: colorHex),
                size: 32
            )
        case .asset(let name, let color):
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))

                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(color)
            }
        case .symbol(let systemImage, let color):
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))

                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
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

    private func detailRowSnapshot(
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
            icon: iconSnapshot(for: row, resourceIndex: resourceIndex),
            action: detailAction(for: row)
        )
    }

    private func iconSnapshot(
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

    private func detailAction(for row: AppNotificationRecord) -> NotificationCenterDetailAction? {
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

    private func openGroup(
        _ group: NotificationCenterGroupSummary,
        resourceIndex: NotificationCenterResourceIndex,
        metadataIndex: NotificationCenterMetadataIndex
    ) {
        let unreadRowIDs = group.rows
            .filter { !$0.isRead || $0.readAt == nil }
            .map(\.id)
        selectedGroupDetailItems = []
        selectedGroupResourceIndex = resourceIndex
        let route = NotificationCenterGroupRoute(
            id: group.id,
            title: group.id.title,
            unreadRowIDs: unreadRowIDs
        )
        selectedGroupRoute = route

        Task { @MainActor in
            await Task.yield()
            guard selectedGroupRoute?.id == group.id else {
                return
            }
            let detailRows = group.rows.map { row in
                detailRowSnapshot(
                    for: row,
                    resourceIndex: resourceIndex,
                    metadataIndex: metadataIndex
                )
            }
            selectedGroupDetailItems = NotificationCenterGrouping.bottomAnchoredDetailItems(
                for: detailRows,
                calendar: calendar
            )
        }
    }

    @MainActor
    private func closeGroupDetail() {
        selectedGroupRoute = nil
        resetGroupDetailState()
    }

    @MainActor
    private func resetGroupDetailState() {
        selectedGroupDetailItems = []
        selectedGroupResourceIndex = NotificationCenterResourceIndex(wallets: [], categories: [], bills: [])
        refreshRenderSnapshotCache()
    }

    @MainActor
    private func markGroupAsReadAfterOpening(_ rowIDs: [UUID]) async {
        try? await Task.sleep(nanoseconds: Self.groupReadDelayNanoseconds)

        let unreadRows = rowIDs
            .compactMap(rowRecord(for:))
            .filter { !$0.isRead || $0.readAt == nil }
        guard !unreadRows.isEmpty else { return }

        let needsRemoteReadSync = markAsRead(
            unreadRows,
            updatesBadgeCount: false,
            pushesRemoteReadState: false
        )

        MistiaNotificationStore.updateAppBadgeCount(
            in: modelContext,
            userID: sessionStore.activeLocalProfileUserID
        )
        if needsRemoteReadSync {
            pushNotificationReadState()
        }
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
        case .transaction:
            return .transactions
        case .wallet, .category:
            return .settings
        case .budget, .goal, .card, .debt, .bill, .due, .installment, .familyTransfer:
            return .planning
        case .permission, nil:
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

    private func respond(to rowID: UUID, approve: Bool) {
        guard let row = rowRecord(for: rowID) else {
            return
        }
        respond(to: row, approve: approve)
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
                    title: L10n.notifications.notificationcenter.couldnTRespond,
                    message: familyContextStore.lastErrorMessage ?? L10n.notifications.notificationcenter.mistiaCouldnTSendThisResponseYet
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
            return row.title
            
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
            if let metadata = metadataIndex.stringMetadata(for: row),
               metadata["joined_user_id"] != nil || metadata["invite_id"] != nil {
                return L10n.notifications.notificationcenter.newMember
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
            return row.body
            
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
                if metadata["joined_user_id"] != nil || metadata["invite_id"] != nil {
                    // This is a join notification. Use backend body which is already good.
                    return row.body
                }
                
                if let actionRaw = metadata["action"] {
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
        approve
            ? L10n.notifications.notificationcenter.mistiaWillSyncTheChangeToCloud
            : L10n.notifications.notificationcenter.noChangeWillBePushedToCloud
    }

    private func permissionRequesterName(for row: AppNotificationRecord) -> String {
        familyContextStore.displayName(for: row.actorUserID)
            ?? L10n.notifications.notificationcenter.thisMember
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
            referenceDate: .now,
            calendar: calendar
        )
        await familyContextStore.refreshNotifications(sessionStore: sessionStore)
        refreshRenderSnapshotCache()
    }

    private var notificationPurpleAccent: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
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
        let unreadCount = unreadCount

        MistiaHeaderCircleButton(action: action) {
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
                        .accessibilityLabel(
                            L10n.notifications.notificationcenter.valueUnreadNotifications(String(describing: unreadCount))
                        )
                }
            }
        }
    }

    private func badgeText(for unreadCount: Int) -> String {
        unreadCount > 99 ? "99+" : "\(unreadCount)"
    }
}

private struct NotificationDetailActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let foreground: Color

    private var fill: Color {
        colorScheme == .dark ? .white.opacity(0.11) : .black.opacity(0.07)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
