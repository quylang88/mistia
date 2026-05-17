import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class SyncCoordinatorFamilyCloudFirstTests: XCTestCase {
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
            XCTAssertFalse(remoteStore.forceUpsertCalled)
            XCTAssertFalse(remoteStore.conditionalUpdateCalled)
            XCTAssertTrue(coordinator.queuedMutations().contains(mutation))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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
    let remoteRecord: MistiaSyncUploadRecord
    var conditionalUpdateCalled = false
    var forceUpsertCalled = false

    init(snapshot: MistiaRemoteSnapshot, remoteRecord: MistiaSyncUploadRecord) {
        self.snapshot = snapshot
        self.remoteRecord = remoteRecord
    }

    func fetchSnapshot(session: SupabaseAuthSession, subjectUserID: UUID?) async throws -> MistiaRemoteSnapshot {
        snapshot
    }

    func fetchRecord(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        remoteRecord.entity == entity && remoteRecord.id == recordID ? remoteRecord : nil
    }

    func create(
        _ record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord {
        record
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
