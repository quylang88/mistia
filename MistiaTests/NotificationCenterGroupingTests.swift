import Foundation
import XCTest
@testable import Mistia

final class NotificationCenterGroupingTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testGroupIDMapsPendingRequestsAndResolvedPermissionSeparately() {
        let pendingPermission = notification(
            key: "pending-permission",
            kind: .permissionRequestReceived,
            actionState: .pending
        )
        let resolvedPermission = notification(
            key: "resolved-permission",
            kind: .permissionRequestReceived,
            actionState: .approved
        )
        let familyTransaction = notification(
            key: "family-transaction",
            kind: .familyActivity,
            resourceType: .transaction
        )
        let familyWallet = notification(
            key: "family-wallet",
            kind: .familyActivity,
            resourceType: .wallet
        )

        XCTAssertEqual(NotificationCenterGrouping.groupID(for: pendingPermission), .actionRequests)
        XCTAssertEqual(NotificationCenterGrouping.groupID(for: resolvedPermission), .access)
        XCTAssertEqual(NotificationCenterGrouping.groupID(for: familyTransaction), .familyCashflow)
        XCTAssertEqual(NotificationCenterGrouping.groupID(for: familyWallet), .familyData)
    }

    func testSummariesOmitEmptyGroupsCountUnreadAndSortByLatestNotification() throws {
        let olderUnreadBudget = notification(
            key: "budget-old",
            createdAt: makeDate(year: 2026, month: 5, day: 21, hour: 9),
            kind: .budgetWarning,
            isRead: false
        )
        let newestReadBill = notification(
            key: "bill-new",
            createdAt: makeDate(year: 2026, month: 5, day: 23, hour: 11),
            kind: .billPaymentRequired,
            isRead: true,
            resourceType: .bill
        )
        let middleUnreadBill = notification(
            key: "bill-middle",
            createdAt: makeDate(year: 2026, month: 5, day: 22, hour: 10),
            kind: .billOverdue,
            isRead: false,
            resourceType: .bill
        )

        let summaries = NotificationCenterGrouping.summaries(
            for: [olderUnreadBudget, newestReadBill, middleUnreadBill]
        )

        XCTAssertEqual(summaries.map(\.id), [.bills, .budgets])
        let billSummary = try XCTUnwrap(summaries.first { $0.id == .bills })
        XCTAssertEqual(billSummary.latestRow.key, "bill-new")
        XCTAssertEqual(billSummary.unreadCount, 1)
        XCTAssertEqual(billSummary.rows.map(\.key), ["bill-middle", "bill-new"])
    }

    func testDaySectionsSortOldestDayAndOldestRowFirst() throws {
        let newest = notification(
            key: "newest",
            createdAt: makeDate(year: 2026, month: 5, day: 24, hour: 18),
            kind: .creditCardStatementReady,
            resourceType: .card
        )
        let oldest = notification(
            key: "oldest",
            createdAt: makeDate(year: 2026, month: 5, day: 23, hour: 8),
            kind: .creditCardAutoPaymentFailed,
            resourceType: .card
        )
        let middle = notification(
            key: "middle",
            createdAt: makeDate(year: 2026, month: 5, day: 24, hour: 9),
            kind: .creditCardAutoPaymentSucceeded,
            resourceType: .card
        )

        let sections = NotificationCenterGrouping.daySections(
            for: [newest, oldest, middle],
            calendar: calendar
        )

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].rows.map(\.key), ["oldest"])
        XCTAssertEqual(sections[1].rows.map(\.key), ["middle", "newest"])
        XCTAssertEqual(sections.flatMap(\.rows).last?.key, "newest")
    }

    func testDetailItemsShowNewestNotificationsFirst() throws {
        let newest = notification(
            key: "newest",
            createdAt: makeDate(year: 2026, month: 5, day: 24, hour: 18),
            kind: .creditCardStatementReady,
            resourceType: .card
        )
        let oldest = notification(
            key: "oldest",
            createdAt: makeDate(year: 2026, month: 5, day: 23, hour: 8),
            kind: .creditCardAutoPaymentFailed,
            resourceType: .card
        )
        let middle = notification(
            key: "middle",
            createdAt: makeDate(year: 2026, month: 5, day: 24, hour: 9),
            kind: .creditCardAutoPaymentSucceeded,
            resourceType: .card
        )

        let items = NotificationCenterGrouping.detailItems(
            for: [newest, oldest, middle].map(detailSnapshot),
            calendar: calendar
        )
        let renderedRowKeys = items.compactMap { item -> String? in
            if case .row(let row) = item.kind {
                return row.key
            }
            return nil
        }

        XCTAssertEqual(renderedRowKeys, ["newest", "middle", "oldest"])
        XCTAssertEqual(renderedRowKeys.first, "newest")
    }

    func testDetailSectionsGroupRowsByNewestDayWithNewestRowsFirst() throws {
        let newest = notification(
            key: "newest",
            createdAt: makeDate(year: 2026, month: 5, day: 24, hour: 18),
            kind: .creditCardStatementReady,
            resourceType: .card
        )
        let oldest = notification(
            key: "oldest",
            createdAt: makeDate(year: 2026, month: 5, day: 23, hour: 8),
            kind: .creditCardAutoPaymentFailed,
            resourceType: .card
        )
        let middle = notification(
            key: "middle",
            createdAt: makeDate(year: 2026, month: 5, day: 24, hour: 9),
            kind: .creditCardAutoPaymentSucceeded,
            resourceType: .card
        )

        let sections = NotificationCenterGrouping.detailSections(
            for: [newest, oldest, middle].map(detailSnapshot),
            calendar: calendar
        )

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].rows.map(\.key), ["newest", "middle"])
        XCTAssertEqual(sections[1].rows.map(\.key), ["oldest"])
    }

    func testPermissionResponseApprovedBodySummarizesUserVisibleResult() {
        XCTAssertEqual(
            NotificationCenterDisplayText.permissionResponseBody(approve: true),
            L10n.notifications.notificationcenter.permissionRequestApprovedBody
        )
    }

    func testPermissionResponseRejectedBodySummarizesUserVisibleResult() {
        XCTAssertEqual(
            NotificationCenterDisplayText.permissionResponseBody(approve: false),
            L10n.notifications.notificationcenter.permissionRequestRejectedBody
        )
    }

    func testFamilyTransferReceivedBodyNamesWalletAndAmount() {
        XCTAssertEqual(
            NotificationCenterDisplayText.familyTransferReceivedBody(
                actorName: "Linh",
                walletName: "Ví chính",
                amountText: "1.000 ¥",
                fallbackBody: "fallback"
            ),
            L10n.notifications.notificationcenter.valueJustTransferredValueIntoYourValue(
                "Linh",
                "1.000 ¥",
                "Ví chính"
            )
        )
    }

    func testFamilyTransferReceivedBodyFallsBackToServerBodyWhenAmountIsMissing() {
        MistiaAppLanguage.persist(.english)
        defer {
            UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
            UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        }

        XCTAssertEqual(
            NotificationCenterDisplayText.familyTransferReceivedBody(
                actorName: "Linh",
                walletName: "Ví chính",
                amountText: nil,
                fallbackBody: "Linh đã chuyển tiền vào ví của bạn."
            ),
            "Linh just transferred money into your Ví chính."
        )
    }

    func testFamilyActivityTitleUsesCurrentAppLanguageInsteadOfStoredTitle() {
        MistiaAppLanguage.persist(.english)
        defer {
            UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
            UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        }

        XCTAssertEqual(
            NotificationCenterDisplayText.familyActivityTitle(
                resourceType: .transaction,
                actionRaw: "created",
                isMemberJoin: false,
                fallbackTitle: "Thu chi mới"
            ),
            L10n.shared.sync.mistiasynccoordinator.newTransaction
        )
    }

    func testFamilyMemberJoinBodyUsesCurrentAppLanguageInsteadOfStoredBody() {
        MistiaAppLanguage.persist(.english)
        defer {
            UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
            UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        }

        XCTAssertEqual(
            NotificationCenterDisplayText.memberJoinedBody(
                actorName: "Linh",
                fallbackBody: "Linh vừa tham gia gia đình."
            ),
            "Linh joined the family."
        )
    }

    private func notification(
        key: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_777_800_000),
        kind: MistiaAppNotificationKind,
        source: MistiaAppNotificationSource = .system,
        isRead: Bool = false,
        resourceType: MistiaFamilyNotificationResourceType? = nil,
        actionState: MistiaNotificationActionState? = nil
    ) -> AppNotificationRecord {
        AppNotificationRecord(
            key: key,
            createdAt: createdAt,
            title: key,
            body: key,
            kind: kind,
            source: source,
            isRead: isRead,
            resourceType: resourceType,
            actionState: actionState
        )
    }

    private func detailSnapshot(_ row: AppNotificationRecord) -> NotificationCenterDetailRowSnapshot {
        NotificationCenterDetailRowSnapshot(
            id: row.id,
            key: row.key,
            createdAt: row.createdAt,
            title: row.title,
            body: row.body,
            icon: .fallback,
            action: nil
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components) ?? .distantPast
    }
}
