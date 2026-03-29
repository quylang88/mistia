import SwiftUI

struct DashboardDump: Decodable {
    let headerTitle: String
    let balance: BalanceSectionDump
    let budgets: [BudgetRowDump]
    let upcomingBills: [UpcomingBillDump]
    let recentTransactions: [TransactionRowDump]
}

struct BalanceSectionDump: Decodable {
    let title: String
    let totalBalance: Int
    let incomeThisMonth: Int
    let expenseThisMonth: Int
    let insightTitle: String
    let insightSubtitle: String
    let filterLabel: String
    let chart: [BalanceChartPointDump]
}

struct BalanceChartPointDump: Decodable, Identifiable {
    let label: String
    let value: Int
    let tone: MistiaAccent

    var id: String { label }
}

struct BudgetRowDump: Decodable, Identifiable {
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
}

struct UpcomingBillDump: Decodable, Identifiable {
    let name: String
    let amount: Int
    let dueTime: String
    let icon: String
    let accent: MistiaAccent

    var id: String { name }
}

struct TransactionRowDump: Decodable, Identifiable {
    let merchant: String
    let amount: Int
    let timeLabel: String
    let icon: String
    let accent: MistiaAccent
    let kind: TransactionKind

    var id: String { merchant + timeLabel }
}

enum TransactionKind: String, Decodable {
    case expense
    case income
}

enum MistiaAccent: String, Decodable {
    case mint
    case teal
    case cyan
    case indigo
    case amber
    case coral
    case rose
    case slate
    case sky

    var color: Color {
        switch self {
        case .mint:
            .mint
        case .teal:
            .teal
        case .cyan:
            .cyan
        case .indigo:
            .indigo
        case .amber:
            Color(red: 0.97, green: 0.66, blue: 0.25)
        case .coral:
            Color(red: 0.98, green: 0.46, blue: 0.41)
        case .rose:
            Color(red: 0.96, green: 0.36, blue: 0.56)
        case .slate:
            Color(red: 0.55, green: 0.58, blue: 0.67)
        case .sky:
            Color(red: 0.39, green: 0.68, blue: 1.0)
        }
    }
}

enum MistiaNumberFormatter {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

extension Int {
    var mistiaCurrency: String {
        let number = NSNumber(value: self)
        return (MistiaNumberFormatter.currency.string(from: number) ?? "\(self)") + "đ"
    }

    var mistiaAxisLabel: String {
        if self >= 1_000_000 {
            return "\(self / 1_000_000)M"
        }
        if self >= 1_000 {
            return "\(self / 1_000)K"
        }
        return "\(self)"
    }
}
