import Foundation

nonisolated enum TransactionGeneratedTitle {
    private typealias LocalizedTitle = (MistiaAppLanguage) -> String

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

    static func isBalanceAdjustmentTitle(_ title: String) -> Bool {
        isKnownGeneratedTitle(title, titleProvider: balanceAdjustment(language:))
    }

    static func debt(_ intent: TransactionDebtIntent, language: MistiaAppLanguage = .current) -> String {
        intent.title(language: language)
    }

    static func localizedDisplayTitle(
        rawTitle: String,
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype?,
        debtIntent: TransactionDebtIntent?,
        categoryID: UUID?,
        categorySystemKey: String? = nil,
        language: MistiaAppLanguage = .current
    ) -> String {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return rawTitle
        }

        for titleProvider in titleProviders(
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            categoryID: categoryID,
            categorySystemKey: categorySystemKey
        ) where isKnownGeneratedTitle(trimmedTitle, titleProvider: titleProvider) {
            return titleProvider(language)
        }

        return rawTitle
    }

    static func localizedDisplayTitle(
        for record: TransactionRecordSnapshot,
        language: MistiaAppLanguage = .current
    ) -> String {
        localizedDisplayTitle(
            rawTitle: record.title,
            primaryKind: record.primaryKind,
            transferSubtype: record.transferSubtype,
            debtIntent: record.debtIntent,
            categoryID: record.categoryID,
            language: language
        )
    }

    private static func titleProviders(
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype?,
        debtIntent: TransactionDebtIntent?,
        categoryID: UUID?,
        categorySystemKey: String?
    ) -> [LocalizedTitle] {
        switch primaryKind {
        case .transfer:
            switch transferSubtype {
            case .internalTransfer:
                return [internalTransfer(language:)]
            case .familyTransfer:
                return [
                    familyTransferSent(language:),
                    familyTransferReceived(language:)
                ]
            case .debt:
                if let debtIntent {
                    return [{ debt(debtIntent, language: $0) }]
                }
                return TransactionDebtIntent.allCases.map { intent in
                    { debt(intent, language: $0) }
                }
            case nil:
                return []
            }
        case .expense, .income:
            guard isBalanceAdjustmentCategory(categoryID, systemKey: categorySystemKey) else { return [] }
            return [balanceAdjustment(language:)]
        }
    }

    private static func isKnownGeneratedTitle(
        _ title: String,
        titleProvider: LocalizedTitle
    ) -> Bool {
        let normalizedTitle = normalized(title)
        return MistiaAppLanguage.allCases.contains { language in
            normalized(titleProvider(language)) == normalizedTitle
        }
    }

    private static func isBalanceAdjustmentCategory(
        _ categoryID: UUID?,
        systemKey: String?
    ) -> Bool {
        categoryID == MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID
            || categoryID == MistiaSystemCategoryIdentity.balanceAdjustmentIncomeID
            || systemKey == MistiaSystemCategoryKey.balanceAdjustmentExpense.rawValue
            || systemKey == MistiaSystemCategoryKey.balanceAdjustmentIncome.rawValue
    }

    private static func normalized(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
