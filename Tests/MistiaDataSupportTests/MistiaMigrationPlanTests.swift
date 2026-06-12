import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class MistiaMigrationPlanTests: XCTestCase {
    func testV4StoreOpensWithPauseDefaults() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let billID = UUID()
        try createCurrentV4Store(at: storeURL, billID: billID)

        let container = try openCurrentStore(at: storeURL)
        let context = ModelContext(container)
        let bills = try context.fetch(FetchDescriptor<RecurringBillPlan>())

        XCTAssertEqual(bills.map(\.id), [billID])
        XCTAssertEqual(bills.first?.name, "Internet")
        XCTAssertEqual(bills.first?.scheduleKind, .recurring)
        XCTAssertEqual(bills.first?.resolvedPaymentStartDay, 12)
        XCTAssertFalse(bills.first?.resolvedHasExplicitDueDate ?? true)
        XCTAssertFalse(bills.first?.isPaused ?? true)
        XCTAssertNil(bills.first?.pausedAt)
        XCTAssertNil(bills.first?.resumeStartMonth)

        bills.first?.autoPayEnabled = true
        bills.first?.autoPayDay = 10
        try context.save()

        let reopenedContainer = try openCurrentStore(at: storeURL)
        let reopenedBills = try ModelContext(reopenedContainer).fetch(FetchDescriptor<RecurringBillPlan>())
        XCTAssertEqual(reopenedBills.first?.autoPayEnabled, true)
        XCTAssertEqual(reopenedBills.first?.autoPayDay, 10)
    }

    func testMigrationPlanUsesFrozenLegacySchemasAndCurrentV6() {
        let schemaNames = MistiaMigrationPlan.schemas.map { String(reflecting: $0) }
        let v4ModelNames = MistiaSchemaV4.models.map { String(reflecting: $0) }
        let v5ModelNames = MistiaSchemaV5.models.map { String(reflecting: $0) }
        let v6ModelNames = MistiaSchemaV6.models.map { String(reflecting: $0) }

        XCTAssertEqual(schemaNames.count, Set(schemaNames).count)
        XCTAssertEqual(schemaNames, [
            "MistiaCoreLogic.MistiaSchemaV4",
            "MistiaCoreLogic.MistiaSchemaV5",
            "MistiaCoreLogic.MistiaSchemaV6"
        ])
        XCTAssertEqual(MistiaMigrationPlan.stages.count, 1)
        XCTAssertTrue(v4ModelNames.contains("MistiaCoreLogic.MistiaSchemaV4Models.RecurringBillPlan"))
        XCTAssertFalse(v4ModelNames.contains("MistiaCoreLogic.RecurringBillPlan"))
        XCTAssertTrue(v5ModelNames.contains("MistiaCoreLogic.RecurringBillPlan"))
        XCTAssertTrue(v5ModelNames.contains("MistiaCoreLogic.MistiaSchemaV5Models.LedgerTransaction"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.LedgerTransaction"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.SettlementGroup"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.SettlementParticipant"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.SettlementObligation"))
    }

    func testPendingSettlementsMigrationIncludesPreparingParticipantsAndStatus() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260611125548_pending_settlements.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create table if not exists public.settlement_participants"))
        XCTAssertTrue(migration.contains("kind_raw_value in ('resale', 'sharedExpense')"))
        XCTAssertTrue(migration.contains("status_raw_value in ('preparing', 'open', 'partiallySettled', 'settled')"))
        XCTAssertTrue(migration.contains("is_archived boolean not null default false"))
        XCTAssertTrue(migration.contains("archived_at timestamptz"))
        XCTAssertTrue(migration.contains("display_name text not null default ''"))
        XCTAssertTrue(migration.contains("normalized_key text"))
        XCTAssertTrue(migration.contains("is_self boolean not null default false"))
        XCTAssertTrue(migration.contains("settlement_participants_group_id_idx"))
        XCTAssertTrue(migration.contains("settlement_participants_family_select"))
    }

    func testFamilyTransferRPCMigrationGuardsPermissionsAndWritesBothRows() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260523120000_family_transfer_rpc.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create or replace function public.create_family_transfer"))
        XCTAssertTrue(migration.contains("public.shared_active_family_id(actor_id, p_recipient_user_id)"))
        XCTAssertTrue(migration.contains("public.can_operate_wallet(p_destination_wallet_id)"))
        XCTAssertTrue(migration.contains("p_amount_minor <= 0"))
        XCTAssertTrue(migration.contains("'familyTransfer'"))
        XCTAssertEqual(migration.components(separatedBy: "insert into public.ledger_transactions").count - 1, 2)
        XCTAssertTrue(migration.contains("insert into public.family_notifications"))
        XCTAssertTrue(migration.contains("'family-transfer:' || recipient_transaction_id::text"))
        XCTAssertTrue(migration.contains("grant execute on function public.create_family_transfer"))
    }

    func testFamilyTransferNoteUpdateMigrationIncludesNoteParameter() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260523130000_update_family_transfer_note.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create or replace function public.create_family_transfer"))
        XCTAssertTrue(migration.contains("p_note text default null"))
        XCTAssertTrue(migration.contains("sender_note || chr(10) || chr(10) || trim(p_note)"))
        XCTAssertTrue(migration.contains("recipient_note || chr(10) || chr(10) || trim(p_note)"))
        XCTAssertTrue(migration.contains("grant execute on function public.create_family_transfer(uuid, uuid, uuid, uuid, bigint, timestamptz, text)"))
    }

    func testFamilyTransferMetadataAndNoteFixMigration() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260524000000_fix_family_transfer_notification_metadata_and_note.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create or replace function public.create_family_transfer"))
        XCTAssertTrue(migration.contains("p_note text default null"))
        XCTAssertTrue(migration.contains("sender_note := trim(p_note);"))
        XCTAssertTrue(migration.contains("recipient_note := trim(p_note);"))
        XCTAssertTrue(migration.contains("amount_minor', p_amount_minor::text"))
        XCTAssertTrue(migration.contains("grant execute on function public.create_family_transfer(uuid, uuid, uuid, uuid, bigint, timestamptz, text)"))
    }

    func testFamilyTransferLocalizedTitleMigrationAddsClientTitleParameters() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260608090000_family_transfer_localized_titles.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("p_sender_title text default null"))
        XCTAssertTrue(migration.contains("p_recipient_title text default null"))
        XCTAssertTrue(migration.contains("coalesce(nullif(trim(p_sender_title), ''), 'Chuyển tiền gia đình')"))
        XCTAssertTrue(migration.contains("coalesce(nullif(trim(p_recipient_title), ''), 'Nhận tiền gia đình')"))
        XCTAssertTrue(migration.contains("uuid, uuid, uuid, uuid, bigint, bigint, text, text, text, text, timestamptz, text, text, text"))
    }

    private func createCurrentV4Store(at storeURL: URL, billID: UUID) throws {
        let schema = Schema(versionedSchema: MistiaSchemaV4.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(
            MistiaSchemaV4.RecurringBillPlan(
                id: billID,
                name: "Internet",
                iconSymbolName: "wifi",
                amountMinor: 4_200,
                dueDay: 12,
                frequencyMonths: 1
            )
        )
        try context.save()
    }

    private func openCurrentStore(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)

        return try MistiaDataStack.LaunchState.openContainer(
            schema: schema,
            configuration: configuration,
            storeURL: storeURL,
            fileManager: .default
        )
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "mistia-migration-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("store")
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func removeStoreArtifacts(at storeURL: URL) throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        let prefix = storeURL.lastPathComponent
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
