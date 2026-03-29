import SwiftUI

struct PlanningScreenDump: Decodable {
    let headerTitle: String
    let tabs: [PlanningTopTabDump]
    let summary: PlanningSummaryDump
    let budgetSectionTitle: String
    let budgets: [PlanningBudgetItemDump]
    let watchSectionTitle: String
    let watchItems: [PlanningWatchItemDump]
    let goalsPlaceholder: PlanningPlaceholderDump
    let recurringPlaceholder: PlanningPlaceholderDump
}

struct PlanningTopTabDump: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
}

struct PlanningSummaryDump: Decodable {
    let totalBudget: Int
    let spent: Int
    let remaining: Int

    var progress: Double {
        guard totalBudget > 0 else { return 0 }
        return min(Double(spent) / Double(totalBudget), 1)
    }

    var progressText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

struct PlanningBudgetItemDump: Decodable, Identifiable {
    let name: String
    let spent: Int
    let limit: Int
    let daysRemainingText: String
    let icon: String
    let accent: MistiaAccent

    var id: String { name }

    var progress: Double {
        guard limit > 0 else { return 0 }
        return min(Double(spent) / Double(limit), 1)
    }

    var percentText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

enum PlanningWatchTone: String, Decodable {
    case alert
    case calm

    var color: Color {
        switch self {
        case .alert:
            Color(red: 0.97, green: 0.43, blue: 0.46)
        case .calm:
            .mint
        }
    }
}

struct PlanningWatchItemDump: Decodable, Identifiable {
    let name: String
    let spent: Int
    let limit: Int
    let trailingAmount: Int
    let statusText: String
    let tone: PlanningWatchTone
    let icon: String
    let accent: MistiaAccent

    var id: String { name }

    var progress: Double {
        guard limit > 0 else { return 0 }
        return min(Double(spent) / Double(limit), 1)
    }
}

struct PlanningPlaceholderDump: Decodable {
    let title: String
    let message: String
    let icon: String
}
