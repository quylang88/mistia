import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class FamilyScopedDataTests: XCTestCase {
    func testSelfAndMemberContextsUseStrictOwnerScopedTransactions() throws {
        let selfUserID = UUID()
        let memberUserID = UUID()
        let container = try makeContainer()
        let sessionStore = makeSessionStore(container: container, userID: selfUserID)
        let familyContextStore = makeFamilyContextStore(container: container, currentUserID: selfUserID)

        let selfWallet = makeWallet(name: "Self cash")
        let memberWallet = makeWallet(name: "Member cash")
        let selfTransactionCreatedByMember = makeTransaction(title: "Self transaction", wallet: selfWallet)
        let memberTransactionCreatedBySelf = makeTransaction(title: "Member transaction", wallet: memberWallet)

        let scopes = [
            OwnedRecordScope(entity: .wallet, recordID: selfWallet.id, ownerUserID: selfUserID),
            OwnedRecordScope(entity: .wallet, recordID: memberWallet.id, ownerUserID: memberUserID),
            OwnedRecordScope(entity: .transaction, recordID: selfTransactionCreatedByMember.id, ownerUserID: selfUserID),
            OwnedRecordScope(entity: .transaction, recordID: memberTransactionCreatedBySelf.id, ownerUserID: memberUserID)
        ]
        let audits = [
            TransactionAuditRecord(
                transactionID: selfTransactionCreatedByMember.id,
                createdByUserID: memberUserID,
                lastModifiedByUserID: memberUserID
            ),
            TransactionAuditRecord(
                transactionID: memberTransactionCreatedBySelf.id,
                createdByUserID: selfUserID,
                lastModifiedByUserID: selfUserID
            )
        ]
        let transactions = [
            selfTransactionCreatedByMember,
            memberTransactionCreatedBySelf
        ]

        familyContextStore.activeContext = .personalSelf
        XCTAssertEqual(
            visibleHistoryIDs(
                transactions,
                audits: audits,
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            ),
            [selfTransactionCreatedByMember.id]
        )
        XCTAssertEqual(
            visibleFinancialIDs(
                transactions,
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            ),
            [selfTransactionCreatedByMember.id]
        )
        XCTAssertEqual(
            FamilyScopedData.visible(
                [selfWallet, memberWallet],
                entity: .wallet,
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            ).map(\.id),
            [selfWallet.id]
        )

        familyContextStore.activeContext = FamilyContext(scope: .member(userID: memberUserID))
        XCTAssertEqual(
            visibleHistoryIDs(
                transactions,
                audits: audits,
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            ),
            [memberTransactionCreatedBySelf.id]
        )
        XCTAssertEqual(
            visibleFinancialIDs(
                transactions,
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            ),
            [memberTransactionCreatedBySelf.id]
        )
        XCTAssertEqual(
            FamilyScopedData.visible(
                [selfWallet, memberWallet],
                entity: .wallet,
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            ).map(\.id),
            [memberWallet.id]
        )
    }

    private func visibleHistoryIDs(
        _ transactions: [LedgerTransaction],
        audits: [TransactionAuditRecord],
        scopes: [OwnedRecordScope],
        familyContextStore: FamilyContextStore,
        sessionStore: SessionStore
    ) -> [UUID] {
        FamilyScopedData.visibleTransactionsForHistory(
            transactions,
            audits: audits,
            scopes: scopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        ).map(\.id)
    }

    private func visibleFinancialIDs(
        _ transactions: [LedgerTransaction],
        scopes: [OwnedRecordScope],
        familyContextStore: FamilyContextStore,
        sessionStore: SessionStore
    ) -> [UUID] {
        FamilyScopedData.visibleTransactionsForFinancial(
            transactions,
            scopes: scopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        ).map(\.id)
    }

    private func makeWallet(name: String) -> LedgerWallet {
        LedgerWallet(
            name: name,
            kind: .cash,
            iconSymbolName: "wallet.pass.fill",
            iconColorHex: "#6E56CF"
        )
    }

    private func makeTransaction(title: String, wallet: LedgerWallet) -> LedgerTransaction {
        LedgerTransaction(
            primaryKind: .expense,
            title: title,
            amountMinor: 1_000,
            sourceWallet: wallet
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
            userDefaults: UserDefaults(suiteName: "MistiaFamilyScopedDataTests.\(UUID().uuidString)") ?? .standard,
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
