import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class SyncCoordinatorFamilyCloudFirstTests: XCTestCase {
    func testOutboxDecodesPersistedSnakeCaseIDKeys() throws {
        let transactionID = UUID()
        let subjectUserID = UUID()
        let deviceID = UUID()
        let defaults = UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard
        let key = "family-outbox-decode"
        defaults.set(
            """
            [{"base_version":0,"device_id":"\(deviceID.uuidString)","entity":"ledger_transactions","kind":"upsert","modified_at":"2026-05-19T08:29:03.970Z","record_id":"\(transactionID.uuidString)","subject_user_id":"\(subjectUserID.uuidString)"}]
            """.data(using: .utf8),
            forKey: key
        )

        let outbox = MistiaSyncOutbox(defaults: defaults, key: key)
        XCTAssertEqual(outbox.allMutations.count, 1)
        XCTAssertEqual(outbox.allMutations.first?.recordID, transactionID)
        XCTAssertEqual(outbox.allMutations.first?.subjectUserID, subjectUserID)
        XCTAssertEqual(outbox.allMutations.first?.deviceID, deviceID)
    }

    func testFamilyCloudFirstPushRequiresRefreshWhenRemoteVersionChanged() async throws {
        let viewerUserID = UUID()
        let memberUserID = UUID()
        let categoryID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let container = try makeContainer()
        try insertCustomCategory(
            id: categoryID,
            name: "Local member category",
            ownerUserID: memberUserID,
            updatedAt: updatedAt,
            remoteVersion: 1,
            in: container
        )

        let remoteRow = RemoteTransactionCategory(
            userID: memberUserID,
            id: categoryID,
            name: "Cloud member category",
            kindRawValue: TransactionCategoryKind.expense.rawValue,
            iconSymbolName: "fork.knife",
            iconColorHex: "#FF8A00",
            isFavorite: false,
            parentCategoryID: nil,
            hierarchyRoleRawValue: TransactionCategoryHierarchyRole.child.rawValue,
            systemKey: nil,
            isSystem: false,
            sortOrder: 20,
            isArchived: false,
            archivedAt: nil,
            createdAt: updatedAt,
            updatedAt: updatedAt.addingTimeInterval(600),
            deletedAt: nil,
            syncVersion: 2,
            lastModifiedByDeviceID: UUID()
        )
        let remoteStore = FamilyConflictRemoteStore(
            snapshot: MistiaRemoteSnapshot(
                wallets: [],
                creditCardProfiles: [],
                categories: [remoteRow],
                transactions: [],
                budgetPlans: [],
                savingsGoals: [],
                recurringBillPlans: [],
                installmentPlans: [],
                dueOccurrences: []
            ),
            remoteRecord: .category(remoteRow)
        )
        let outbox = MistiaSyncOutbox(
            defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
            key: "family-conflict"
        )
        let coordinator = SyncCoordinator(
            modelContainer: container,
            remoteStore: remoteStore,
            outbox: outbox,
            deviceID: UUID()
        )
        let mutation = MistiaSyncMutation(
            entity: .category,
            recordID: categoryID,
            subjectUserID: memberUserID,
            kind: .upsert,
            modifiedAt: updatedAt.addingTimeInterval(900),
            baseVersion: 1
        )
        coordinator.queue(mutation)

        do {
            _ = try await coordinator.pushQueuedFamilyOwnerMutationsCloudFirst(
                [mutation],
                session: makeSession(userID: viewerUserID)
            )
            XCTFail("Expected family cloud-first conflict")
        } catch MistiaFamilyCloudFirstPushError.remoteChanged {
            XCTAssertEqual(remoteStore.fetchSnapshotCallCount, 0)
            XCTAssertFalse(remoteStore.forceUpsertCalled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFamilyCloudFirstTransactionCreateDoesNotBootstrapCategoryCatalog() async throws {
        let viewerUserID = UUID()
        let memberUserID = UUID()
        let walletID = UUID()
        let categoryID = UUID()
        let transactionID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let container = try makeContainer()
        let context = ModelContext(container)
        let wallet = LedgerWallet(
            id: walletID,
            name: "PayPay",
            kind: .payPay,
            iconSymbolName: "wallet.pass.fill",
            iconColorHex: "#6E56CF",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            remoteVersion: 1
        )
        let category = TransactionCategory(
            id: categoryID,
            name: "Member meals",
            kind: .expense,
            iconSymbolName: "fork.knife",
            iconColorHex: "#FF8A00",
            hierarchyRole: .child,
            isSystem: false,
            cloudSyncEnabled: true,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            remoteVersion: 1
        )
        let transaction = LedgerTransaction(
            id: transactionID,
            primaryKind: .expense,
            title: "Member lunch",
            amountMinor: 690,
            occurredAt: updatedAt,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            sourceWallet: wallet,
            category: category
        )
        context.insert(wallet)
        context.insert(category)
        context.insert(transaction)
        context.insert(OwnedRecordScope(entity: .wallet, recordID: walletID, ownerUserID: memberUserID, updatedAt: updatedAt))
        context.insert(OwnedRecordScope(entity: .category, recordID: categoryID, ownerUserID: memberUserID, updatedAt: updatedAt))
        context.insert(OwnedRecordScope(entity: .transaction, recordID: transactionID, ownerUserID: memberUserID, updatedAt: updatedAt))
        context.insert(
            TransactionAuditRecord(
                transactionID: transactionID,
                createdByUserID: viewerUserID,
                lastModifiedByUserID: viewerUserID,
                updatedAt: updatedAt
            )
        )
        try context.save()

        let remoteStore = FamilyConflictRemoteStore()
        let outbox = MistiaSyncOutbox(
            defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
            key: "family-transaction-create"
        )
        let coordinator = SyncCoordinator(
            modelContainer: container,
            remoteStore: remoteStore,
            outbox: outbox,
            deviceID: UUID()
        )
        let mutation = MistiaSyncMutation(
            entity: .transaction,
            recordID: transactionID,
            subjectUserID: memberUserID,
            kind: .upsert,
            modifiedAt: updatedAt,
            baseVersion: 0
        )
        coordinator.queue(mutation)

        let pushed = try await coordinator.pushQueuedFamilyOwnerMutationsCloudFirst(
            [mutation],
            session: makeSession(userID: viewerUserID)
        )

        XCTAssertTrue(pushed)
        XCTAssertEqual(remoteStore.fetchSnapshotCallCount, 0)
        XCTAssertEqual(remoteStore.fetchedEntities, [.transaction])
        XCTAssertFalse(remoteStore.forceUpsertCalled)
        let createdTransaction = remoteStore.createdRecords.compactMap { record -> RemoteLedgerTransaction? in
            guard case .transaction(let row) = record else { return nil }
            return row
        }.first
        XCTAssertEqual(createdTransaction?.userID, memberUserID)
        XCTAssertEqual(createdTransaction?.createdByUserID, viewerUserID)
        XCTAssertEqual(createdTransaction?.categoryID, categoryID)
        XCTAssertFalse(outbox.contains(entity: .transaction, recordID: transactionID))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func insertCustomCategory(
        id: UUID,
        name: String,
        ownerUserID: UUID,
        updatedAt: Date,
        remoteVersion: Int64,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let category = TransactionCategory(
            id: id,
            name: name,
            kind: .expense,
            iconSymbolName: "fork.knife",
            iconColorHex: "#FF8A00",
            isFavorite: true,
            hierarchyRole: .child,
            isSystem: false,
            cloudSyncEnabled: true,
            sortOrder: 20,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            remoteVersion: remoteVersion
        )
        context.insert(category)
        context.insert(OwnedRecordScope(entity: .category, recordID: id, ownerUserID: ownerUserID, updatedAt: updatedAt))
        try context.save()
    }

    private func makeSession(userID: UUID) -> SupabaseAuthSession {
        SupabaseAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "bearer",
            expiresAt: .now.addingTimeInterval(3_600),
            user: SupabaseAuthUser(
                id: userID,
                email: "viewer@example.com",
                userMetadata: SupabaseUserMetadata(
                    displayName: "Viewer",
                    fullName: nil,
                    name: nil,
                    avatarURL: nil,
                    picture: nil
                )
            )
        )
    }
}

@MainActor
private final class FamilyConflictRemoteStore: MistiaRemoteStore {
    let snapshot: MistiaRemoteSnapshot
    let remoteRecord: MistiaSyncUploadRecord?
    var conditionalUpdateCalled = false
    var forceUpsertCalled = false
    var fetchSnapshotCallCount = 0
    var fetchedEntities: [MistiaSyncEntity] = []
    var createdRecords: [MistiaSyncUploadRecord] = []

    init(
        snapshot: MistiaRemoteSnapshot = MistiaRemoteSnapshot(
            wallets: [],
            creditCardProfiles: [],
            categories: [],
            transactions: [],
            budgetPlans: [],
            savingsGoals: [],
            recurringBillPlans: [],
            installmentPlans: [],
            dueOccurrences: []
        ),
        remoteRecord: MistiaSyncUploadRecord? = nil
    ) {
        self.snapshot = snapshot
        self.remoteRecord = remoteRecord
    }

    func fetchSnapshot(session: SupabaseAuthSession, subjectUserID: UUID?) async throws -> MistiaRemoteSnapshot {
        fetchSnapshotCallCount += 1
        return snapshot
    }

    func fetchRecord(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        fetchedEntities.append(entity)
        guard let remoteRecord else { return nil }
        return remoteRecord.entity == entity && remoteRecord.id == recordID ? remoteRecord : nil
    }

    func create(
        _ record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord {
        createdRecords.append(record)
        return record
    }

    func conditionalUpdate(
        _ record: MistiaSyncUploadRecord,
        expectedVersion: Int64,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        conditionalUpdateCalled = true
        return nil
    }

    func conditionalDelete(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        expectedVersion: Int64,
        modifiedAt: Date,
        deviceID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        nil
    }

    func forceUpsert(
        _ record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord {
        forceUpsertCalled = true
        return record
    }

    func createFamilyActivityNotification(
        _ event: RemoteFamilyActivityNotificationEvent,
        session: SupabaseAuthSession
    ) async throws {}
}
