import Foundation

struct TransactionScreenDump: Decodable {
    let headerTitle: String
    let timeframeLabel: String
    let walletLabel: String
    let summary: TransactionSummaryDump
    let sections: [TransactionSectionDump]
    let filterSheet: TransactionFilterSheetDump
}

struct TransactionSummaryDump: Decodable {
    let expense: Int
    let income: Int
    let totalTransactions: Int
}

struct TransactionSectionDump: Decodable, Identifiable {
    let title: String
    let trailingLabel: String
    let items: [TransactionListItemDump]

    var id: String { title + trailingLabel }
}

struct TransactionListItemDump: Decodable, Identifiable {
    let merchant: String
    let subtitle: String
    let amount: Int
    let icon: String
    let accent: MistiaAccent
    let kind: TransactionKind

    var id: String { merchant + subtitle }
}

struct TransactionFilterSheetDump: Decodable {
    let title: String
    let code: String
    let rows: [TransactionFilterRowDump]
    let resetLabel: String
    let applyLabel: String
}

struct TransactionFilterRowDump: Decodable, Identifiable {
    let title: String
    let value: String
    let icon: String

    var id: String { title }
}
