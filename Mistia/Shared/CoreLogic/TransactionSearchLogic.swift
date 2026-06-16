import Foundation

enum TransactionSearchLogic {
    static func filters(for query: String) -> TransactionFilterState? {
        guard let normalizedQuery = TransactionLogic.normalizeCounterpartyName(query),
              !normalizedQuery.isEmpty
        else { return nil }

        var filters = TransactionFilterState(timeScope: .allTime, statusScope: .all)
        filters.searchText = query
        return filters
    }
}
