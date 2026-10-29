import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class CreditCardPaymentCurrencyTests: XCTestCase {
    private func fixture() throws -> (ModelContainer, ModelContext, LedgerWallet, LedgerWallet) {
        let schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let wallet = LedgerWallet(name: "Cash", kind: .cash, iconSymbolName: "wallet.pass.fill", iconColorHex: "#000000", currencyCode: "JPY", openingBalanceMinor: 9007199254740993)
        let card = LedgerWallet(name: "Card", kind: .creditCard, iconSymbolName: "creditcard.fill", iconColorHex: "#000000", currencyCode: "VND")
        context.insert(wallet); context.insert(card); try context.save()
        return (container, context, card, wallet)
    }
    func testOnlySameValidNormalizedCurrenciesAreEligible() {
        for (card, wallet, expected) in [("JPY", "JPY", true), ("VND", "VND", true), (" jpy ", "JPY", true),
            ("VND", "JPY", false), ("", "", false), ("US", "US", false), ("123", "123", false)] {
            XCTAssertEqual(PlanningLogic.creditCardPaymentWalletIsEligible(cardCurrencyCode: card, walletCurrencyCode: wallet), expected)
        }
    }
    func testPersistedForeignWalletIsRejectedBeforeAnyFinancialMutation() throws {
        let (_, context, card, wallet) = try fixture()
        XCTAssertThrowsError(try PlanningCreditCardPaymentSupport.validateWallet(sourceID: card.id, wallet: wallet, context: context))
        XCTAssertFalse(context.hasChanges); XCTAssertEqual(wallet.openingBalanceMinor, 9007199254740993)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerTransaction>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DueOccurrenceRecord>()), 0)
    }
    func testPersistedCurrencyChangeRevokesAPreviouslyValidSelection() throws {
        let (_, context, card, wallet) = try fixture(); card.currencyCode = "JPY"; try context.save()
        XCTAssertNoThrow(try PlanningCreditCardPaymentSupport.validateWallet(sourceID: card.id, wallet: wallet, context: context))
        card.currencyCode = "VND"; try context.save()
        XCTAssertThrowsError(try PlanningCreditCardPaymentSupport.validateWallet(sourceID: card.id, wallet: wallet, context: context))
        XCTAssertFalse(context.hasChanges)
    }
    func testDeletedArchivedMissingOrNonCardSourceCannotPay() throws {
        let (_, context, card, wallet) = try fixture(); card.currencyCode = "JPY"; try context.save()
        XCTAssertThrowsError(try PlanningCreditCardPaymentSupport.validateWallet(sourceID: UUID(), wallet: wallet, context: context))
        for mutation in [{ card.deletedAt = .now }, { card.deletedAt = nil; card.isArchived = true }, { card.isArchived = false; card.kind = .cash }, { card.kind = .creditCard; wallet.kind = .creditCard }] {
            mutation(); try context.save()
            XCTAssertThrowsError(try PlanningCreditCardPaymentSupport.validateWallet(sourceID: card.id, wallet: wallet, context: context))
        }
    }
    func testSameCurrencyPreservesExactImportedMoneyAndRejectsDeletedPaymentWallet() throws {
        let (_, context, card, wallet) = try fixture(); card.currencyCode = " jpy "; try context.save()
        XCTAssertNoThrow(try PlanningCreditCardPaymentSupport.validateWallet(sourceID: card.id, wallet: wallet, context: context))
        XCTAssertEqual(card.currencyCode, " jpy "); XCTAssertEqual(wallet.openingBalanceMinor, 9007199254740993); XCTAssertFalse(context.hasChanges)
        wallet.deletedAt = .now; try context.save()
        XCTAssertThrowsError(try PlanningCreditCardPaymentSupport.validateWallet(sourceID: card.id, wallet: wallet, context: context))
    }

    func testPaymentTitleInterpolationAndCurrencyMessageUseAllThreeCatalogLanguages() {
        XCTAssertEqual(L10n.management.managementcreditcardstatement.paymentTitle("Card %@", language: .english), "Card payment: Card %@")
        XCTAssertEqual(L10n.management.managementcreditcardstatement.paymentTitle("Card", language: .vietnamese), "Thanh toán thẻ Card")
        XCTAssertEqual(L10n.management.managementcreditcardstatement.paymentTitle("Card", language: .japanese), "カード支払い: Card")
        XCTAssertTrue(L10n.management.managementcreditcardstatement.currencyMismatch(language: .vietnamese).contains("cùng tiền tệ"))
        XCTAssertTrue(L10n.management.managementcreditcardstatement.currencyMismatch(language: .english).contains("same currency"))
        XCTAssertTrue(L10n.management.managementcreditcardstatement.currencyMismatch(language: .japanese).contains("同じ通貨"))
    }

}
