import SwiftUI
import UIKit

struct TransactionShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum TransactionStatementExportSupport {
    static func write(document: TransactionStatementDocument) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mistia-statements", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let url = directory.appendingPathComponent(document.filename)
        let data = Data(document.html.utf8)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        try data.write(to: url, options: .atomic)
        return url
    }
}

struct TransactionShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

extension LedgerWallet {
    var overviewWalletSnapshot: OverviewWalletSnapshot? {
        guard !isArchived else { return nil }

        return OverviewWalletSnapshot(
            id: id,
            name: name,
            kind: kind,
            openingBalanceMinor: openingBalanceMinor,
            currencyCode: currencyCode,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }

    func overviewCreditCardStatementAccountSnapshot(
        records: [TransactionRecordSnapshot]
    ) -> OverviewCreditCardStatementAccountSnapshot? {
        guard kind == .creditCard, !isArchived, let profile = creditCardProfile else {
            return nil
        }

        let debt = max(
            TransactionLogic.effectiveBalance(
                for: TransactionWalletSnapshot(
                    id: id,
                    kind: .creditCard,
                    openingBalanceMinor: openingBalanceMinor
                ),
                records: records
            ),
            0
        )
        
        let availableCredit = max(profile.creditLimitMinor - debt, 0)

        return OverviewCreditCardStatementAccountSnapshot(
            id: id,
            walletID: id,
            walletName: name,
            iconSymbolName: iconSymbolName,
            issuerName: profile.issuerName,
            network: profile.network,
            last4: profile.last4,
            creditLimitMinor: profile.creditLimitMinor,
            currentDebtMinor: debt,
            availableCreditMinor: availableCredit,
            statementClosingDay: profile.statementClosingDay,
            paymentDueDay: profile.paymentDueDay,
            paymentSourceWalletName: profile.paymentSourceWallet?.name,
            currencyCode: currencyCode,
            openedAt: createdAt
        )
    }
}

extension LedgerTransaction {
    var overviewSnapshot: OverviewTransactionSnapshot {
        OverviewTransactionSnapshot(
            id: id,
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: entryStatus,
            title: title,
            note: note,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            createdAt: createdAt,
            sourceWalletID: sourceWallet?.id,
            sourceWalletName: sourceWallet?.name,
            sourceWalletKind: sourceWallet?.kind,
            destinationWalletID: destinationWallet?.id,
            destinationWalletName: destinationWallet?.name,
            destinationWalletKind: destinationWallet?.kind,
            categoryID: category?.id,
            categoryName: category?.localizedDisplayName,
            categoryIconSymbolName: category?.iconSymbolName,
            categoryColorHex: category?.iconColorHex,
            categoryParentID: category?.parentCategory?.id,
            categoryParentName: category?.parentCategory?.localizedDisplayName,
            categoryParentIconSymbolName: category?.parentCategory?.iconSymbolName,
            categoryParentColorHex: category?.parentCategory?.iconColorHex,
            counterpartyName: counterpartyName,
            isArchived: isArchived
        )
    }
}

extension OverviewTint {
    var color: Color {
        switch self {
        case .green:
            Color(hex: "#2DAA9E")
        case .orange:
            Color(hex: "#F59B3F")
        case .red:
            Color(hex: "#F45C7E")
        case .blue:
            Color(hex: "#5B7BFF")
        }
    }
}
