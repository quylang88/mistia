import Foundation

nonisolated enum TransactionGeneratedTitle {
    static func internalTransfer(language: MistiaAppLanguage = .current) -> String {
        L10n.transactions.transactioneditor.internalTransfer(language: language)
    }

    static func familyTransferSent(language: MistiaAppLanguage = .current) -> String {
        L10n.transactions.generatedTitle.familyTransferSent(language: language)
    }

    static func familyTransferReceived(language: MistiaAppLanguage = .current) -> String {
        L10n.transactions.generatedTitle.familyTransferReceived(language: language)
    }

    static func balanceAdjustment(language: MistiaAppLanguage = .current) -> String {
        L10n.transactions.generatedTitle.balanceAdjustment(language: language)
    }

    static func debt(_ intent: TransactionDebtIntent, language: MistiaAppLanguage = .current) -> String {
        intent.title(language: language)
    }
}
