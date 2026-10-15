import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class InstallmentPaymentCurrencyTests: XCTestCase {
    private func fixture() throws -> (ModelContainer, ModelContext, InstallmentPlan, LedgerWallet) {
        let schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let wallet = LedgerWallet(name: "Cash", kind: .cash, iconSymbolName: "wallet.pass.fill", iconColorHex: "#000000", currencyCode: "JPY", openingBalanceMinor: 9007199254740993)
        let plan = InstallmentPlan(name: "Loan", iconSymbolName: "mistia.plan.loan", amountPerCycleMinor: 9007199254740993, dueDay: 15,
            paymentWallet: wallet, currencyCode: "VND")
        context.insert(wallet); context.insert(plan); try context.save()
        return (container, context, plan, wallet)
    }
    func testMixedCurrencyPersistedWalletIsRejectedBeforeAnyPaymentMutation() throws {
        let (_, context, plan, wallet) = try fixture()
        XCTAssertThrowsError(try PlanningInstallmentPaymentSupport.validateWallet(sourceID: plan.id, wallet: wallet, context: context)) {
            XCTAssertEqual($0 as? PlanningDuePaymentError, .installmentCurrencyMismatch)
        }
        XCTAssertFalse(context.hasChanges); XCTAssertEqual(plan.amountPerCycleMinor, 9007199254740993)
        XCTAssertEqual(wallet.openingBalanceMinor, 9007199254740993)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerTransaction>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DueOccurrenceRecord>()), 0)
    }
    func testPersistedCurrencyChangeInvalidatesAPreviouslyEligibleSelection() throws {
        let (_, context, plan, wallet) = try fixture(); plan.currencyCode = "JPY"; try context.save()
        XCTAssertNoThrow(try PlanningInstallmentPaymentSupport.validateWallet(sourceID: plan.id, wallet: wallet, context: context))
        plan.currencyCode = "USD"; try context.save()
        XCTAssertThrowsError(try PlanningInstallmentPaymentSupport.validateWallet(sourceID: plan.id, wallet: wallet, context: context))
        XCTAssertFalse(context.hasChanges)
    }
    func testSameNormalizedCurrencyPreservesImportedMetadataAndExactAmounts() throws {
        let (_, context, plan, wallet) = try fixture(); plan.currencyCode = " jpy "; try context.save()
        XCTAssertNoThrow(try PlanningInstallmentPaymentSupport.validateWallet(sourceID: plan.id, wallet: wallet, context: context))
        XCTAssertEqual(plan.currencyCode, " jpy "); XCTAssertEqual(plan.amountPerCycleMinor, 9007199254740993); XCTAssertFalse(context.hasChanges)
    }
    func testMissingDeletedArchivedPlanAndDeletedCardWalletCannotBypassPersistenceGuard() throws {
        let (_, context, plan, wallet) = try fixture(); plan.currencyCode = "JPY"; try context.save()
        XCTAssertThrowsError(try PlanningInstallmentPaymentSupport.validateWallet(sourceID: UUID(), wallet: wallet, context: context))
        plan.deletedAt = .now; try context.save()
        XCTAssertThrowsError(try PlanningInstallmentPaymentSupport.validateWallet(sourceID: plan.id, wallet: wallet, context: context))
        plan.deletedAt = nil; plan.isArchived = true; try context.save()
        XCTAssertThrowsError(try PlanningInstallmentPaymentSupport.validateWallet(sourceID: plan.id, wallet: wallet, context: context))
        plan.isArchived = false; wallet.deletedAt = .now; try context.save()
        XCTAssertThrowsError(try PlanningInstallmentPaymentSupport.validateWallet(sourceID: plan.id, wallet: wallet, context: context))
        wallet.deletedAt = nil; wallet.kind = .creditCard; try context.save()
        XCTAssertThrowsError(try PlanningInstallmentPaymentSupport.validateWallet(sourceID: plan.id, wallet: wallet, context: context))
    }
}
