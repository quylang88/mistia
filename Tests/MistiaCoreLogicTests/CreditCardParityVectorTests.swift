import Foundation
import XCTest
@testable import MistiaCoreLogic

final class CreditCardParityVectorTests: XCTestCase {
    private struct Document: Decodable { let version:Int; let owner:String; let card:String; let cash:String; let cases:[Vector] }
    private struct Vector: Decodable {
        let name:String; let month:String; let zone:String; let reference:String; let openedAt:String
        let closingDay:Int; let dueDay:Int; let paymentSource:String?; let sourceBalance:Int64?
        let transactions:[Record]; let occurrences:[Occurrence]; let expected:Expected?
    }
    private struct Record: Decodable {
        let id:String; let kind:String; let amount:Int64; let at:String; let source:String?
        let destination:String?; let destinationAmount:Int64?; let subtype:String?; let intent:String?
        let owner:String?; let status:String?; let archived:Bool?; let deleted:Bool?; let category:String?; let title:String?
    }
    private struct Occurrence: Decodable {let month:String;let amount:Int64?;let status:String;let linked:String?}
    private struct Expected: Decodable {let amount:Int64;let state:String;let status:String;let linked:String?;let closing:String;let due:String;let decision:String;let availableCredit:Int64}
    private func date(_ raw:String) -> Date {ISO8601DateFormatter().date(from:raw)!}
    func testSharedAndroidCreditCardStatementVectors() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let document=try JSONDecoder().decode(Document.self,from:Data(contentsOf:root.appendingPathComponent("contracts/golden/credit-card-statements-v1.json")))
        XCTAssertEqual(document.version,1)
        let card=UUID(uuidString:document.card)!
        for vector in document.cases {
            let calendar=MistiaCalendar.gregorian(timeZone:TimeZone(identifier:vector.zone)!)
            let parts=vector.month.split(separator:"-")
            let month=calendar.date(from:DateComponents(year:Int(parts[0]),month:Int(parts[1]),day:1))!
            let records=vector.transactions.filter {($0.owner ?? document.owner)==document.owner && $0.deleted != true}.map {record in
                TransactionRecordSnapshot(id:UUID(uuidString:record.id)!,primaryKind:TransactionPrimaryKind(rawValue:record.kind)!,
                    transferSubtype:record.subtype.flatMap(TransactionTransferSubtype.init(rawValue:)),debtIntent:record.intent.flatMap(TransactionDebtIntent.init(rawValue:)),
                    entryStatus:TransactionEntryStatus(rawValue:record.status ?? "posted")!,title:record.title ?? "Record",note:nil,amountMinor:record.amount,
                    destinationAmountMinor:record.destinationAmount,isArchived:record.archived ?? false,occurredAt:date(record.at),createdAt:date(record.at),
                    sourceWalletID:record.source.flatMap(UUID.init(uuidString:)),sourceWalletKind:record.source==document.card ? .creditCard : .cash,
                    destinationWalletID:record.destination.flatMap(UUID.init(uuidString:)),destinationWalletKind:record.destination==document.card ? .creditCard : nil,
                    categoryID:record.category.flatMap(UUID.init(uuidString:)),counterpartyName:nil,normalizedCounterpartyKey:nil)
            }
            let cardWallet=TransactionWalletSnapshot(id:card,kind:.creditCard,openingBalanceMinor:0)
            let balance=TransactionLogic.creditCardBalance(creditLimitMinor:100_000,wallet:cardWallet,
                balanceIndex:TransactionLogic.walletBalanceIndex(wallets:[cardWallet],records:records))
            let account=PlanningCreditCardAccountSnapshot(id:UUID(),walletID:card,walletName:"Card",issuerName:"Issuer",network:.visa,last4:"1234",
                dueDay:vector.dueDay,statementClosingDay:vector.closingDay,paymentSourceWalletID:vector.paymentSource.flatMap(UUID.init(uuidString:)),
                paymentSourceWalletName:"Cash",currencyCode:"JPY",currentDebtMinor:balance.currentDebtMinor,availableCreditMinor:balance.availableCreditMinor,openedAt:date(vector.openedAt))
            let occurrences=vector.occurrences.map {row in PlanningDueOccurrenceSnapshot(id:UUID(),sourceKind:.creditCard,sourceID:card,
                selectedMonthKey:row.month,scheduledDate:date(vector.reference),amountMinorSnapshot:row.amount,
                status:PlanningDueOccurrenceStatus(rawValue:row.status)!,linkedTransactionID:row.linked.flatMap(UUID.init(uuidString:)))}
            let rows=PlanningLogic.creditCardStatementItems(accounts:[account],records:records,occurrences:occurrences,statementMonths:[month],
                referenceDate:date(vector.reference),calendar:calendar)
            guard let expected=vector.expected else {XCTAssertTrue(rows.isEmpty,vector.name);continue}
            let actual=try XCTUnwrap(rows.first,vector.name);XCTAssertEqual(rows.count,1,vector.name)
            XCTAssertEqual(actual.availableCreditMinor,expected.availableCredit,vector.name)
            XCTAssertEqual(actual.amountMinor,expected.amount,vector.name);XCTAssertEqual(actual.state.rawValue,expected.state,vector.name)
            XCTAssertEqual(actual.status.rawValue,expected.status,vector.name);XCTAssertEqual(actual.linkedTransactionID?.uuidString.lowercased(),expected.linked,vector.name)
            XCTAssertEqual(actual.closingDate,date(expected.closing),vector.name);XCTAssertEqual(actual.dueDate,date(expected.due),vector.name)
            let decision=PlanningLogic.creditCardAutoPaymentDecision(statement:actual,sourceWalletBalanceMinor:vector.sourceBalance,
                referenceDate:date(vector.reference),calendar:calendar)
            let kind:String
            switch decision {case .notDue:kind="notDue";case .alreadyPaid:kind="alreadyPaid";case .missingLinkedWallet:kind="missingLinkedWallet"
            case .insufficientFunds:kind="insufficientFunds";case .payable:kind="payable"}
            XCTAssertEqual(kind,expected.decision,vector.name)
        }
    }
}
