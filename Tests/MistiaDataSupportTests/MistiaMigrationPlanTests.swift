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

    func testMigrationPlanUsesFrozenLegacySchemasAndCurrentV8() {
        let schemaNames = MistiaMigrationPlan.schemas.map { String(reflecting: $0) }
        let v4ModelNames = MistiaSchemaV4.models.map { String(reflecting: $0) }
        let v5ModelNames = MistiaSchemaV5.models.map { String(reflecting: $0) }
        let v6ModelNames = MistiaSchemaV6.models.map { String(reflecting: $0) }
        let v7ModelNames = MistiaSchemaV7.models.map { String(reflecting: $0) }
        let v8ModelNames = MistiaSchemaV8.models.map { String(reflecting: $0) }

        XCTAssertEqual(schemaNames.count, Set(schemaNames).count)
        XCTAssertEqual(schemaNames, [
            "MistiaCoreLogic.MistiaSchemaV4",
            "MistiaCoreLogic.MistiaSchemaV5",
            "MistiaCoreLogic.MistiaSchemaV6",
            "MistiaCoreLogic.MistiaSchemaV7",
            "MistiaCoreLogic.MistiaSchemaV8"
        ])
        XCTAssertEqual(MistiaMigrationPlan.stages.count, 3)
        XCTAssertEqual(
            MistiaLegacyV4ToV5MigrationPlan.schemas.map { String(reflecting: $0) },
            ["MistiaCoreLogic.MistiaSchemaV4", "MistiaCoreLogic.MistiaSchemaV5"]
        )
        XCTAssertTrue(v4ModelNames.contains("MistiaCoreLogic.MistiaSchemaV4Models.RecurringBillPlan"))
        XCTAssertFalse(v4ModelNames.contains("MistiaCoreLogic.RecurringBillPlan"))
        XCTAssertTrue(v5ModelNames.contains("MistiaCoreLogic.RecurringBillPlan"))
        XCTAssertTrue(v5ModelNames.contains("MistiaCoreLogic.MistiaSchemaV5Models.LedgerTransaction"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.LedgerTransaction"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.SettlementGroup"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.SettlementParticipant"))
        XCTAssertFalse(v6ModelNames.contains("MistiaCoreLogic.SettlementObligation"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.InvestmentChannel"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.MistiaSchemaV7InvestmentModels.InvestmentAsset"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.MistiaSchemaV7InvestmentModels.InvestmentTrade"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.InvestmentValuation"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.InvestmentWalletPosting"))
        XCTAssertTrue(v8ModelNames.contains("MistiaCoreLogic.InvestmentAsset"))
        XCTAssertTrue(v8ModelNames.contains("MistiaCoreLogic.InvestmentTrade"))
        XCTAssertFalse(v8ModelNames.contains("MistiaCoreLogic.MistiaSchemaV7InvestmentModels.InvestmentAsset"))
    }

    func testV7InvestmentStoreMigratesWithoutOpeningPositionOrFees() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let ownerID = UUID()
        let channelID = UUID()
        let assetID = UUID()
        let tradeID = UUID()
        let fundingWalletID = UUID()
        let fundingLedgerID = InvestmentLedgerIdentity.derivedID(eventID: tradeID, component: "funding")
        let fundingPostingID = InvestmentLedgerIdentity.derivedID(eventID: tradeID, component: "funding-posting")
        let v7Schema = Schema(versionedSchema: MistiaSchemaV7.self)
        let v7Configuration = ModelConfiguration("default", schema: v7Schema, url: storeURL)
        do {
            let container = try ModelContainer(for: v7Schema, configurations: [v7Configuration])
            let context = ModelContext(container)
            let fundingWallet = LedgerWallet(
                id: fundingWalletID,
                name: "Funding",
                kind: .cash,
                iconSymbolName: "banknote.fill",
                iconColorHex: "#000000",
                currencyCode: "JPY"
            )
            context.insert(fundingWallet)
            context.insert(
                LedgerWallet(
                    id: InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerID),
                    name: "Investment",
                    kind: .investment,
                    iconSymbolName: LedgerWalletKind.investment.defaultIconSymbolName,
                    iconColorHex: LedgerWalletKind.investment.defaultColorHex,
                    currencyCode: "JPY"
                )
            )
            context.insert(InvestmentChannel(id: channelID, ownerUserID: ownerID, name: "Legacy"))
            context.insert(
                MistiaSchemaV7.InvestmentAsset(
                    id: assetID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    name: "Legacy asset",
                    symbol: "OLD",
                    currencyCode: "JPY",
                    openingQuantityDecimalString: "2",
                    openingCostMinor: 100
                )
            )
            let trade = MistiaSchemaV7.InvestmentTrade(
                id: tradeID,
                ownerUserID: ownerID,
                channelID: channelID,
                assetID: assetID,
                kindRawValue: InvestmentTradeKind.buy.rawValue,
                quantityDecimalString: "1",
                grossAmountMinor: 120,
                feeMinor: 10,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 120,
                accountingFeeMinor: 10,
                accountingCurrencyCode: "JPY",
                fundingWalletID: fundingWalletID
            )
            trade.fundingWalletCurrencyCode = "JPY"
            trade.fundingWalletAmountMinor = 130
            trade.fundingLedgerTransactionID = fundingLedgerID
            trade.positionQuantityAfterDecimalString = "3"
            trade.positionCostBasisAfterMinor = 230
            context.insert(trade)
            context.insert(
                LedgerTransaction(
                    id: fundingLedgerID,
                    primaryKind: .expense,
                    title: "Legacy asset",
                    amountMinor: 130,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0,
                    sourceCurrencyCode: "JPY",
                    reportingCurrencyCode: "JPY",
                    reportingAmountMinor: 130,
                    occurredAt: trade.occurredAt,
                    sourceWallet: fundingWallet
                )
            )
            context.insert(
                InvestmentWalletPosting(
                    id: fundingPostingID,
                    ownerUserID: ownerID,
                    eventID: tradeID,
                    tradeID: tradeID,
                    assetID: assetID,
                    walletID: fundingWalletID,
                    ledgerTransactionID: fundingLedgerID,
                    role: .funding,
                    amountMinor: -130,
                    currencyCode: "JPY",
                    accountingAmountMinor: -130,
                    accountingCurrencyCode: "JPY"
                )
            )
            context.insert(
                SyncConflict(
                    entityRawValue: MistiaSyncEntity.investmentAsset.rawValue,
                    recordID: assetID,
                    conflictKindRawValue: MistiaSyncConflictKind.editEdit.rawValue,
                    localPayloadJSON: """
                    {"id":"\(assetID.uuidString)","name":"Legacy asset","symbol":"OLD","opening_quantity_decimal_string":"2","opening_cost_minor":100}
                    """,
                    remotePayloadJSON: """
                    {"id":"\(assetID.uuidString)","name":"Remote asset","symbol":"REMOTE","opening_quantity_decimal_string":"4","opening_cost_minor":240}
                    """,
                    baseVersion: 1,
                    remoteVersion: 2
                )
            )
            context.insert(
                SyncConflict(
                    entityRawValue: MistiaSyncEntity.investmentTrade.rawValue,
                    recordID: tradeID,
                    conflictKindRawValue: MistiaSyncConflictKind.editEdit.rawValue,
                    localPayloadJSON: """
                    {"id":"\(tradeID.uuidString)","gross_amount_minor":120,"fee_minor":10,"accounting_fee_minor":10}
                    """,
                    remotePayloadJSON: """
                    {"id":"\(tradeID.uuidString)","gross_amount_minor":120,"fee_minor":20,"accounting_fee_minor":20}
                    """,
                    baseVersion: 1,
                    remoteVersion: 2
                )
            )
            try context.save()
        }

        let v8Schema = Schema(versionedSchema: MistiaSchemaV8.self)
        let v8Configuration = ModelConfiguration("default", schema: v8Schema, url: storeURL)
        let migrated = try MistiaDataStack.LaunchState.openContainer(
            schema: v8Schema,
            configuration: v8Configuration,
            storeURL: storeURL,
            fileManager: .default
        )
        let trades = try ModelContext(migrated).fetch(FetchDescriptor<InvestmentTrade>())
        let stored = try XCTUnwrap(trades.first(where: { $0.id == tradeID }))

        XCTAssertEqual(stored.positionQuantityAfter, 1)
        XCTAssertEqual(stored.positionCostBasisAfterMinor, 120)
        XCTAssertEqual(stored.fundingWalletAmountMinor, 120)
        let ledger = try ModelContext(migrated).fetch(FetchDescriptor<LedgerTransaction>())
        let posting = try ModelContext(migrated).fetch(FetchDescriptor<InvestmentWalletPosting>())
        XCTAssertEqual(ledger.first(where: { $0.id == fundingLedgerID })?.amountMinor, 120)
        XCTAssertEqual(ledger.first(where: { $0.id == fundingLedgerID })?.reportingAmountMinor, 120)
        XCTAssertEqual(posting.first(where: { $0.id == fundingPostingID })?.amountMinor, -120)
        XCTAssertEqual(posting.first(where: { $0.id == fundingPostingID })?.accountingAmountMinor, -120)
        let conflicts = try ModelContext(migrated).fetch(FetchDescriptor<SyncConflict>())
        XCTAssertEqual(conflicts.count, 2)
        for conflict in conflicts {
            for payload in [conflict.localPayloadJSON, conflict.remotePayloadJSON] {
                XCTAssertFalse(payload.contains("symbol"))
                XCTAssertFalse(payload.contains("opening_quantity_decimal_string"))
                XCTAssertFalse(payload.contains("opening_cost_minor"))
                XCTAssertFalse(payload.contains("fee_minor"))
                XCTAssertFalse(payload.contains("accounting_fee_minor"))
            }
        }
    }

    func testV7InvestmentMigrationRejectsOversellThatReliedOnOpeningPositionAtomically() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let ownerID = UUID()
        let channelID = UUID()
        let assetID = UUID()
        let tradeID = UUID()
        let capitalWalletID = UUID()
        let v7Schema = Schema(versionedSchema: MistiaSchemaV7.self)
        let v7Configuration = ModelConfiguration("default", schema: v7Schema, url: storeURL)
        do {
            let container = try ModelContainer(for: v7Schema, configurations: [v7Configuration])
            let context = ModelContext(container)
            context.insert(
                LedgerWallet(
                    id: capitalWalletID,
                    name: "Capital return",
                    kind: .bank,
                    iconSymbolName: "building.columns.fill",
                    iconColorHex: "#000000",
                    currencyCode: "JPY"
                )
            )
            context.insert(
                LedgerWallet(
                    id: InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerID),
                    name: "Investment",
                    kind: .investment,
                    iconSymbolName: LedgerWalletKind.investment.defaultIconSymbolName,
                    iconColorHex: LedgerWalletKind.investment.defaultColorHex,
                    currencyCode: "JPY"
                )
            )
            context.insert(InvestmentChannel(id: channelID, ownerUserID: ownerID, name: "Legacy"))
            context.insert(
                MistiaSchemaV7.InvestmentAsset(
                    id: assetID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    name: "Opening-only asset",
                    symbol: "OLD",
                    currencyCode: "JPY",
                    openingQuantityDecimalString: "1",
                    openingCostMinor: 100
                )
            )
            let trade = MistiaSchemaV7.InvestmentTrade(
                id: tradeID,
                ownerUserID: ownerID,
                channelID: channelID,
                assetID: assetID,
                kindRawValue: InvestmentTradeKind.sell.rawValue,
                quantityDecimalString: "1",
                grossAmountMinor: 150,
                feeMinor: 5,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 150,
                accountingFeeMinor: 5,
                accountingCurrencyCode: "JPY",
                capitalReturnWalletID: capitalWalletID
            )
            trade.capitalReturnWalletCurrencyCode = "JPY"
            trade.capitalReturnWalletAmountMinor = 100
            trade.releasedCostBasisMinor = 100
            trade.realizedProfitLossMinor = 45
            trade.positionQuantityAfterDecimalString = "0"
            trade.positionCostBasisAfterMinor = 0
            context.insert(trade)
            try context.save()
        }

        let v8Schema = Schema(versionedSchema: MistiaSchemaV8.self)
        let v8Configuration = ModelConfiguration("default", schema: v8Schema, url: storeURL)
        XCTAssertThrowsError(
            try MistiaDataStack.LaunchState.openContainer(
                schema: v8Schema,
                configuration: v8Configuration,
                storeURL: storeURL,
                fileManager: .default
            )
        )

        let reopenedV7 = try ModelContainer(for: v7Schema, configurations: [v7Configuration])
        let context = ModelContext(reopenedV7)
        let assets = try context.fetch(FetchDescriptor<MistiaSchemaV7.InvestmentAsset>())
        let trades = try context.fetch(FetchDescriptor<MistiaSchemaV7.InvestmentTrade>())
        XCTAssertEqual(assets.first(where: { $0.id == assetID })?.openingQuantityDecimalString, "1")
        XCTAssertEqual(assets.first(where: { $0.id == assetID })?.openingCostMinor, 100)
        XCTAssertEqual(trades.first(where: { $0.id == tradeID })?.accountingFeeMinor, 5)
        XCTAssertEqual(trades.first(where: { $0.id == tradeID })?.realizedProfitLossMinor, 45)
    }

    func testPendingSettlementsMigrationIncludesPreparingParticipantsAndStatus() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260611125548_pending_settlements.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create table if not exists public.settlement_participants"))
        XCTAssertTrue(migration.contains("kind_raw_value in ('sharedExpense')"))
        XCTAssertFalse(migration.contains("create table if not exists public.settlement_obligations"))
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

    func testTransactionCreatorWalletAccessMigrationRestoresCreatorManageBranch() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260616115354_restore_transaction_creator_wallet_access.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create or replace function public.can_manage_transaction"))
        XCTAssertTrue(migration.contains("auth.uid() = created_by_user_id"))
        XCTAssertTrue(migration.contains("public.can_operate_wallet(source_wallet_id)"))
        XCTAssertTrue(migration.contains("public.has_family_permission_grant(owner_user_id, 'transaction', null, 'edit')"))
        XCTAssertTrue(migration.contains("grant execute on function public.can_manage_transaction"))
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
