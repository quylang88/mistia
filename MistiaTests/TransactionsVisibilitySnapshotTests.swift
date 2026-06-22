import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class TransactionsVisibilitySnapshotTests: XCTestCase {
    func testVisibilitySnapshotBuildsSharedTransactionListInputs() throws {
        let selfUserID = UUID()
        let memberUserID = UUID()
        let archivedGroupID = UUID()
        let container = try makeContainer()
        let sessionStore = makeSessionStore(container: container, userID: selfUserID)
        let familyContextStore = makeFamilyContextStore(container: container, currentUserID: selfUserID)
        familyContextStore.activeContext = FamilyContext(scope: .member(userID: memberUserID))

        let selfWallet = makeWallet(name: "Self cash", sortOrder: 0)
        let memberWallet = makeWallet(name: "Member cash", sortOrder: 1)
        let expenseParent = makeCategory(
            name: "Expense",
            kind: .expense,
            hierarchyRole: .parent,
            sortOrder: 0
        )
        let dinnerCategory = makeCategory(
            name: "Dinner",
            kind: .expense,
            parentCategory: expenseParent,
            hierarchyRole: .child,
            sortOrder: 1
        )

        let archivedGroup = SettlementGroup(
            id: archivedGroupID,
            kind: .sharedExpense,
            status: .preparing,
            title: "Archived dinner",
            occurredAt: Date(timeIntervalSince1970: 1_770_000_050),
            totalMinor: 8_000,
            expectedMinor: 8_000,
            organizerUserID: memberUserID,
            isArchived: true,
            archivedAt: Date(timeIntervalSince1970: 1_770_000_200)
        )
        let visibleGroup = SettlementGroup(
            kind: .sharedExpense,
            status: .preparing,
            title: "Visible dinner",
            occurredAt: Date(timeIntervalSince1970: 1_770_000_060),
            totalMinor: 4_000,
            expectedMinor: 4_000,
            organizerUserID: memberUserID
        )
        let linkedArchivedBill = LedgerTransaction(
            primaryKind: .expense,
            title: "Linked bill remains visible",
            amountMinor: 8_000,
            settlementGroupID: archivedGroupID,
            settlementRole: .sharedExpensePaid,
            occurredAt: Date(timeIntervalSince1970: 1_770_000_300),
            sourceWallet: memberWallet,
            category: dinnerCategory
        )
        let generatedArchivedDebt = LedgerTransaction(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            title: "Generated debt hides",
            amountMinor: 4_000,
            settlementGroupID: archivedGroupID,
            settlementRole: .sharedExpensePayable,
            occurredAt: Date(timeIntervalSince1970: 1_770_000_400),
            sourceWallet: memberWallet
        )
        let recentMemberTransaction = LedgerTransaction(
            primaryKind: .expense,
            title: "Recent member expense",
            amountMinor: 1_000,
            occurredAt: Date(timeIntervalSince1970: 1_770_000_500),
            sourceWallet: memberWallet,
            category: dinnerCategory
        )
        let selfTransaction = LedgerTransaction(
            primaryKind: .expense,
            title: "Self expense",
            amountMinor: 1_000,
            occurredAt: Date(timeIntervalSince1970: 1_770_000_600),
            sourceWallet: selfWallet
        )

        let scopes = [
            OwnedRecordScope(entity: .wallet, recordID: selfWallet.id, ownerUserID: selfUserID),
            OwnedRecordScope(entity: .wallet, recordID: memberWallet.id, ownerUserID: memberUserID),
            OwnedRecordScope(entity: .category, recordID: expenseParent.id, ownerUserID: memberUserID),
            OwnedRecordScope(entity: .category, recordID: dinnerCategory.id, ownerUserID: memberUserID),
            OwnedRecordScope(entity: .settlementGroup, recordID: archivedGroup.id, ownerUserID: memberUserID),
            OwnedRecordScope(entity: .settlementGroup, recordID: visibleGroup.id, ownerUserID: memberUserID),
            OwnedRecordScope(entity: .transaction, recordID: linkedArchivedBill.id, ownerUserID: memberUserID),
            OwnedRecordScope(entity: .transaction, recordID: generatedArchivedDebt.id, ownerUserID: memberUserID),
            OwnedRecordScope(entity: .transaction, recordID: recentMemberTransaction.id, ownerUserID: memberUserID),
            OwnedRecordScope(entity: .transaction, recordID: selfTransaction.id, ownerUserID: selfUserID)
        ]

        let snapshot = TransactionsVisibilitySnapshot.make(
            transactions: [
                selfTransaction,
                generatedArchivedDebt,
                linkedArchivedBill,
                recentMemberTransaction
            ],
            wallets: [selfWallet, memberWallet],
            categories: [expenseParent, dinnerCategory],
            settlementGroups: [archivedGroup, visibleGroup],
            settlementParticipants: [],
            ownershipScopes: scopes,
            transactionAuditRecords: [],
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )

        XCTAssertEqual(snapshot.archivedSettlementGroupIDs, [archivedGroupID])
        XCTAssertEqual(snapshot.activeWallets.map(\.id), [memberWallet.id])
        XCTAssertEqual(snapshot.activeTransactions.map(\.id), [
            recentMemberTransaction.id,
            linkedArchivedBill.id
        ])
        XCTAssertEqual(snapshot.walletOwnerMap[memberWallet.id], memberUserID)
        XCTAssertEqual(snapshot.transactionOwnerMap[recentMemberTransaction.id], memberUserID)

        let categorySections = snapshot.categorySections(for: nil)
        XCTAssertEqual(categorySections.map(\.parent.id), [expenseParent.id])
        XCTAssertEqual(categorySections.first?.children.map(\.id), [dinnerCategory.id])
    }

    private func makeWallet(name: String, sortOrder: Int) -> LedgerWallet {
        LedgerWallet(
            name: name,
            kind: .cash,
            iconSymbolName: "wallet.pass.fill",
            iconColorHex: "#6E56CF",
            sortOrder: sortOrder
        )
    }

    private func makeCategory(
        name: String,
        kind: TransactionCategoryKind,
        parentCategory: TransactionCategory? = nil,
        hierarchyRole: TransactionCategoryHierarchyRole,
        sortOrder: Int
    ) -> TransactionCategory {
        TransactionCategory(
            name: name,
            kind: kind,
            iconSymbolName: "tag.fill",
            iconColorHex: "#6E56CF",
            parentCategory: parentCategory,
            hierarchyRole: hierarchyRole,
            sortOrder: sortOrder
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSessionStore(container: ModelContainer, userID: UUID) -> SessionStore {
        let store = SessionStore(
            modelContainer: container,
            userDefaults: UserDefaults(suiteName: "TransactionsVisibilitySnapshotTests.\(UUID().uuidString)") ?? .standard,
            connectivityMonitor: SessionConnectivityMonitor(initialStatus: .disconnected),
            registerBackgroundRefresh: false
        )
        store.summary = SessionSummary(
            userID: userID,
            displayName: "Self",
            email: "self@example.com",
            avatarURL: nil
        )
        return store
    }

    private func makeFamilyContextStore(container: ModelContainer, currentUserID: UUID) -> FamilyContextStore {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let familyID = UUID()
        let store = FamilyContextStore(modelContainer: container)
        store.currentMembership = FamilyMembershipRecord(
            id: UUID(),
            familyID: familyID,
            userID: currentUserID,
            roleRawValue: FamilyRole.owner.rawValue,
            canViewFamilyDashboard: true,
            canViewOthers: true,
            canEditOthers: false,
            canViewWallets: true,
            canViewDebts: true,
            canViewKids: true,
            canEditKids: false,
            deletedAt: nil,
            createdAt: now,
            updatedAt: now
        )
        return store
    }
}
