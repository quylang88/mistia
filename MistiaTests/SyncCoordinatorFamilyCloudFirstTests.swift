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

    func testRemoteSnapshotFingerprintIsCompactAndOrderIndependent() {
        let userID = UUID()
        let walletA = remoteWallet(
            id: UUID(),
            userID: userID,
            name: "First wallet",
            syncVersion: 1
        )
        let walletB = remoteWallet(
            id: UUID(),
            userID: userID,
            name: "Second wallet",
            syncVersion: 2
        )
        let forward = remoteSnapshot(wallets: [walletA, walletB])
        let reversed = remoteSnapshot(wallets: [walletB, walletA])

        XCTAssertEqual(forward.fingerprint, reversed.fingerprint)
        XCTAssertEqual(forward.fingerprint.count, 64)
        XCTAssertNotNil(forward.fingerprint.range(of: "^[0-9a-f]{64}$", options: .regularExpression))

        var changedWallet = walletB
        changedWallet.name = "Changed wallet"
        XCTAssertNotEqual(forward.fingerprint, remoteSnapshot(wallets: [walletA, changedWallet]).fingerprint)
    }

    func testRemoteSnapshotUploadRecordIndexKeepsLatestDuplicateByStorageKey() {
        let userID = UUID()
        let walletID = UUID()
        let older = remoteWallet(
            id: walletID,
            userID: userID,
            name: "Older wallet",
            syncVersion: 1
        )
        var latest = older
        latest.name = "Latest wallet"
        latest.syncVersion = 2

        let snapshot = remoteSnapshot(wallets: [older, latest])
        let key = MistiaSyncUploadRecord.wallet(older).storageKey

        XCTAssertEqual(snapshot.uploadRecordStorageKeys, [key])
        guard case .wallet(let indexedWallet) = snapshot.uploadRecordsByStorageKey[key] else {
            return XCTFail("Expected indexed wallet record")
        }
        XCTAssertEqual(indexedWallet.name, "Latest wallet")
        XCTAssertEqual(indexedWallet.syncVersion, 2)
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
                settlementGroups: [],
                settlementParticipants: [],
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
        XCTAssertEqual(remoteStore.familyNotificationEvents.count, 1)
        XCTAssertEqual(remoteStore.familyNotificationEvents.first?.recipientUserID, memberUserID)
        XCTAssertEqual(remoteStore.familyNotificationEvents.first?.resourceType, .transaction)
        XCTAssertEqual(remoteStore.familyNotificationEvents.first?.resourceID, transactionID)
        XCTAssertFalse(outbox.contains(entity: .transaction, recordID: transactionID))
    }

    func testQueuedTransactionCreateUsesSourceWalletOwnerWhenMutationSubjectIsStale() async throws {
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
            name: "Member wallet",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759",
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
        context.insert(OwnedRecordScope(entity: .transaction, recordID: transactionID, ownerUserID: viewerUserID, updatedAt: updatedAt))
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
            key: "stale-transaction-subject"
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
            subjectUserID: viewerUserID,
            kind: .upsert,
            modifiedAt: updatedAt,
            baseVersion: 0
        )
        coordinator.queue(mutation)

        let pushed = try await coordinator.pushQueuedMutationsOnly(
            [mutation],
            session: makeSession(userID: viewerUserID)
        )

        XCTAssertTrue(pushed)
        XCTAssertEqual(remoteStore.createSubjectUserIDs, [memberUserID])
        let createdTransaction = remoteStore.createdRecords.compactMap { record -> RemoteLedgerTransaction? in
            guard case .transaction(let row) = record else { return nil }
            return row
        }.first
        XCTAssertEqual(createdTransaction?.userID, memberUserID)
        XCTAssertEqual(createdTransaction?.createdByUserID, viewerUserID)
        XCTAssertEqual(remoteStore.familyNotificationEvents.first?.recipientUserID, memberUserID)
        XCTAssertFalse(outbox.contains(entity: .transaction, recordID: transactionID))
    }

    func testFamilyCloudFirstPushKeepsFinanceSyncedWhenActivityNotificationIsForbidden() async throws {
        let viewerUserID = UUID()
        let memberUserID = UUID()
        let walletID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let container = try makeContainer()
        let context = ModelContext(container)
        let wallet = LedgerWallet(
            id: walletID,
            name: "Member cash",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            remoteVersion: 0
        )
        context.insert(wallet)
        context.insert(OwnedRecordScope(entity: .wallet, recordID: walletID, ownerUserID: memberUserID, updatedAt: updatedAt))
        try context.save()

        let remoteStore = FamilyConflictRemoteStore()
        remoteStore.familyNotificationError = SupabaseServiceError.serverMessage(
            "[POST create_family_activity_notification] HTTP 403: forbidden"
        )
        let outbox = MistiaSyncOutbox(
            defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
            key: "family-notification-forbidden"
        )
        let coordinator = SyncCoordinator(
            modelContainer: container,
            remoteStore: remoteStore,
            outbox: outbox,
            deviceID: UUID()
        )
        let mutation = MistiaSyncMutation(
            entity: .wallet,
            recordID: walletID,
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
        XCTAssertEqual(remoteStore.createdRecords.count, 1)
        XCTAssertEqual(remoteStore.familyNotificationEvents.count, 1)
        XCTAssertFalse(outbox.contains(entity: .wallet, recordID: walletID))
    }

    func testRestoredArchivedEventPushesUnarchivedStateToRemote() async throws {
        let userID = UUID()
        let groupID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let archivedAt = updatedAt.addingTimeInterval(-600)
        let container = try makeCurrentContainer()
        let context = ModelContext(container)
        let group = SettlementGroup(
            id: groupID,
            kind: .sharedExpense,
            status: .preparing,
            title: "Trip",
            currencyCode: "JPY",
            occurredAt: updatedAt,
            totalMinor: 12_000,
            expectedMinor: 0,
            settledMinor: 0,
            organizerUserID: userID,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            remoteVersion: 2,
            isArchived: false,
            archivedAt: nil
        )
        context.insert(group)
        context.insert(OwnedRecordScope(entity: .settlementGroup, recordID: groupID, ownerUserID: userID, updatedAt: updatedAt))
        try context.save()

        let remoteArchived = RemoteSettlementGroup(
            userID: userID,
            id: groupID,
            kindRawValue: SettlementKind.sharedExpense.rawValue,
            statusRawValue: SettlementStatus.preparing.rawValue,
            title: "Trip",
            currencyCode: "JPY",
            occurredAt: updatedAt,
            totalMinor: 12_000,
            expectedMinor: 0,
            settledMinor: 0,
            organizerUserID: userID,
            note: nil,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            deletedAt: nil,
            isArchived: true,
            archivedAt: archivedAt,
            syncVersion: 2,
            lastModifiedByDeviceID: nil
        )
        let remoteStore = FamilyConflictRemoteStore(remoteRecord: .settlementGroup(remoteArchived))
        remoteStore.shouldReturnConditionalUpdateRecord = true
        let mutation = MistiaSyncMutation(
            entity: .settlementGroup,
            recordID: groupID,
            subjectUserID: userID,
            kind: .upsert,
            modifiedAt: updatedAt,
            baseVersion: 2
        )
        let localRecord = try XCTUnwrap(
            MistiaSyncLocalStore.exportRecord(
                for: mutation,
                from: container
            )
        )
        guard case .settlementGroup(let localGroupRecord) = localRecord else {
            return XCTFail("Expected local settlement group export")
        }
        XCTAssertFalse(localGroupRecord.isArchived)
        XCTAssertNil(localGroupRecord.archivedAt)
        XCTAssertNotEqual(localRecord.payloadFingerprint, MistiaSyncUploadRecord.settlementGroup(remoteArchived).payloadFingerprint)
        let outbox = MistiaSyncOutbox(
            defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
            key: "restored-event-pushes-unarchived"
        )
        let coordinator = SyncCoordinator(
            modelContainer: container,
            remoteStore: remoteStore,
            outbox: outbox,
            deviceID: UUID()
        )
        coordinator.queue(mutation)

        let pushed = try await coordinator.pushQueuedMutationsOnly(
            [mutation],
            session: makeSession(userID: userID)
        )

        XCTAssertTrue(pushed)
        XCTAssertEqual(remoteStore.conditionalUpdatedRecords.count, 1)
        guard case .settlementGroup(let pushedGroup) = remoteStore.conditionalUpdatedRecords.first else {
            return XCTFail("Expected settlement group update")
        }
        XCTAssertFalse(pushedGroup.isArchived)
        XCTAssertNil(pushedGroup.archivedAt)
        XCTAssertEqual(pushedGroup.syncVersion, 3)
        XCTAssertFalse(outbox.contains(entity: .settlementGroup, recordID: groupID))

        let localGroup = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<SettlementGroup>()).first)
        XCTAssertFalse(localGroup.isArchived)
        XCTAssertNil(localGroup.archivedAt)
        XCTAssertEqual(localGroup.remoteVersion, 3)
    }

    private func remoteWallet(
        id: UUID,
        userID: UUID,
        name: String,
        syncVersion: Int64
    ) -> RemoteLedgerWallet {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        return RemoteLedgerWallet(
            userID: userID,
            id: id,
            name: name,
            kindRawValue: LedgerWalletKind.cash.rawValue,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759",
            currencyCode: "JPY",
            openingBalanceMinor: 0,
            institutionDisplayName: nil,
            institutionPresetKey: nil,
            sortOrder: 0,
            isArchived: false,
            archivedAt: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            syncVersion: syncVersion,
            lastModifiedByDeviceID: UUID()
        )
    }

    private func remoteSnapshot(wallets: [RemoteLedgerWallet]) -> MistiaRemoteSnapshot {
        MistiaRemoteSnapshot(
            wallets: wallets,
            creditCardProfiles: [],
            categories: [],
            settlementGroups: [],
            settlementParticipants: [],
            transactions: [],
            budgetPlans: [],
            savingsGoals: [],
            recurringBillPlans: [],
            installmentPlans: [],
            dueOccurrences: []
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeCurrentContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
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
    var createSubjectUserIDs: [UUID] = []
    var conditionalUpdatedRecords: [MistiaSyncUploadRecord] = []
    var shouldReturnConditionalUpdateRecord = false
    var familyNotificationEvents: [RemoteFamilyActivityNotificationEvent] = []
    var familyNotificationError: Error?

    init(
        snapshot: MistiaRemoteSnapshot = MistiaRemoteSnapshot(
            wallets: [],
            creditCardProfiles: [],
            categories: [],
            settlementGroups: [],
            settlementParticipants: [],
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
        createSubjectUserIDs.append(subjectUserID)
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
        conditionalUpdatedRecords.append(record)
        return shouldReturnConditionalUpdateRecord ? record : nil
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
    ) async throws {
        familyNotificationEvents.append(event)
        if let familyNotificationError {
            throw familyNotificationError
        }
    }
}
