import SwiftUI

public enum OverviewSectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case preparingSettlements
    case budgetFocus
    case upcomingBills
    case recentTransactions
    case investment

    public var id: String { rawValue }

    public var iconSymbolName: String {
        switch self {
        case .preparingSettlements: return "person.2.fill"
        case .budgetFocus: return "chart.bar.fill"
        case .upcomingBills: return "calendar.badge.clock"
        case .recentTransactions: return "clock.arrow.circlepath"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .preparingSettlements:
            return L10n.transactions.settlement.ongoingEvents
        case .budgetFocus:
            return L10n.overview.overview.budgetWatchlist
        case .upcomingBills:
            return L10n.overview.overview.upcomingDueItems
        case .recentTransactions:
            return L10n.overview.overview.recentTransactions
        case .investment:
            return L10n.investment.title
        }
    }
}

public struct OverviewSectionItemConfig: Codable, Identifiable, Equatable, Sendable {
    public let kind: OverviewSectionKind
    public var isVisible: Bool

    public var id: String { kind.rawValue }

    public init(kind: OverviewSectionKind, isVisible: Bool) {
        self.kind = kind
        self.isVisible = isVisible
    }

    public static var defaultConfig: [OverviewSectionItemConfig] {
        [
            OverviewSectionItemConfig(kind: .investment, isVisible: true),
            OverviewSectionItemConfig(kind: .preparingSettlements, isVisible: true),
            OverviewSectionItemConfig(kind: .budgetFocus, isVisible: true),
            OverviewSectionItemConfig(kind: .upcomingBills, isVisible: true),
            OverviewSectionItemConfig(kind: .recentTransactions, isVisible: true)
        ]
    }
}

enum OverviewSectionCustomizationAvailability {
    static func isVisible(in scope: FamilyContext.Scope) -> Bool {
        scope == .personalSelf
    }
}

public enum OverviewSectionConfigStorage {
    public static func encode(_ configs: [OverviewSectionItemConfig]) throws -> Data {
        try JSONEncoder().encode(configs)
    }

    public static func decode(from data: Data) -> [OverviewSectionItemConfig] {
        guard !data.isEmpty,
              let items = try? JSONDecoder().decode([OverviewSectionItemConfig].self, from: data) else {
            return OverviewSectionItemConfig.defaultConfig
        }

        return sanitized(items)
    }

    static func decode(
        remoteItems: [RemoteOverviewSectionItemConfig]?
    ) -> [OverviewSectionItemConfig] {
        guard let remoteItems else {
            return OverviewSectionItemConfig.defaultConfig
        }

        let items = remoteItems.compactMap { item -> OverviewSectionItemConfig? in
            guard let kind = OverviewSectionKind(rawValue: item.kind) else { return nil }
            return OverviewSectionItemConfig(kind: kind, isVisible: item.isVisible)
        }
        return sanitized(items)
    }

    private static func sanitized(
        _ items: [OverviewSectionItemConfig]
    ) -> [OverviewSectionItemConfig] {
        var result = items
        let existingKinds = Set(items.map(\.kind))
        for defaultItem in OverviewSectionItemConfig.defaultConfig {
            if !existingKinds.contains(defaultItem.kind) {
                result.append(defaultItem)
            }
        }
        return result
    }
}
