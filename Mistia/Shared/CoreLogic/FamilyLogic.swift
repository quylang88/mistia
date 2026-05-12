import Foundation

enum FamilyRole: CaseIterable, Codable, Hashable, RawRepresentable {
    typealias RawValue = String

    case owner
    case member
    case kid

    init?(rawValue: String) {
        switch rawValue {
        case "owner":
            self = .owner
        case "member", "viewer", "editor":
            self = .member
        case "kid":
            self = .kid
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .owner:
            "owner"
        case .member:
            "member"
        case .kid:
            "kid"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let storedValue = try container.decode(String.self)
        guard let role = FamilyRole(rawValue: storedValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown family role: \(storedValue)"
            )
        }
        self = role
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct FamilyPermissionPolicy: Codable, Equatable, Hashable {
    var canViewFamilyDashboard: Bool
    var canViewOthers: Bool
    var canEditOthers: Bool
    var canViewWallets: Bool
    var canViewDebts: Bool
    var canViewKids: Bool
    var canEditKids: Bool

    static func preset(for role: FamilyRole) -> FamilyPermissionPolicy {
        switch role {
        case .owner:
            FamilyPermissionPolicy(
                canViewFamilyDashboard: true,
                canViewOthers: true,
                canEditOthers: false,
                canViewWallets: true,
                canViewDebts: true,
                canViewKids: true,
                canEditKids: false
            )
        case .member:
            FamilyPermissionPolicy(
                canViewFamilyDashboard: true,
                canViewOthers: true,
                canEditOthers: false,
                canViewWallets: true,
                canViewDebts: true,
                canViewKids: false,
                canEditKids: false
            )
        case .kid:
            FamilyPermissionPolicy(
                canViewFamilyDashboard: false,
                canViewOthers: false,
                canEditOthers: false,
                canViewWallets: true,
                canViewDebts: false,
                canViewKids: false,
                canEditKids: false
            )
        }
    }
}

struct FamilyContext: Equatable, Hashable {
    enum Scope: Equatable, Hashable {
        case personalSelf
        case familyHome(familyID: UUID)
        case member(userID: UUID)
    }

    var scope: Scope

    static let personalSelf = FamilyContext(scope: .personalSelf)
}

struct FamilyMemberAccessCapabilities: Equatable {
    var canOpenFamilyHome: Bool
    var canInviteMembers: Bool
    var canManageMembers: Bool
    var canViewTarget: Bool
    var canEditTarget: Bool
    var canViewTargetWallets: Bool
    var canViewTargetDebts: Bool

    static let none = FamilyMemberAccessCapabilities(
        canOpenFamilyHome: false,
        canInviteMembers: false,
        canManageMembers: false,
        canViewTarget: false,
        canEditTarget: false,
        canViewTargetWallets: false,
        canViewTargetDebts: false
    )
}

struct FamilyAggregateWalletSnapshot: Equatable {
    enum Kind: String, Equatable {
        case cash
        case bank
        case ewallet
        case creditCard
        case other
    }

    let ownerUserID: UUID
    let kind: Kind
    let balanceMinor: Int64
    let debtMinor: Int64
}

struct FamilyAggregateTransactionSnapshot: Equatable {
    enum Kind: String, Equatable {
        case expense
        case income
        case transfer
    }

    let ownerUserID: UUID
    let categoryName: String?
    let occurredAt: Date
    let kind: Kind
    let amountMinor: Int64
    let isCreditCardPayment: Bool

    init(
        ownerUserID: UUID,
        categoryName: String?,
        occurredAt: Date,
        kind: Kind,
        amountMinor: Int64,
        isCreditCardPayment: Bool = false
    ) {
        self.ownerUserID = ownerUserID
        self.categoryName = categoryName
        self.occurredAt = occurredAt
        self.kind = kind
        self.amountMinor = amountMinor
        self.isCreditCardPayment = isCreditCardPayment
    }
}

struct FamilyTrendPoint: Equatable, Identifiable {
    let date: Date
    let valueMinor: Int64
    var id: Date { date }
}

struct FamilyMemberSpendingSnapshot: Equatable, Identifiable {
    let userID: UUID
    let name: String
    let amountMinor: Int64
    var id: UUID { userID }
}

struct FamilyDonutSegment: Equatable, Identifiable {
    let label: String
    let valueMinor: Int64
    let colorHex: String?
    var id: String { label }
}

struct FamilyInsight: Equatable {
    let text: String
    let isPositive: Bool
}

struct FamilyAggregateSummary: Equatable {
    var totalAssetsMinor: Int64
    var totalDebtMinor: Int64
    var spendableMinor: Int64
    var assetTrend: [FamilyTrendPoint]
    var balanceByWalletKind: [FamilyAggregateWalletSnapshot.Kind: Int64]
    var expenseByCategory: [FamilyDonutSegment]
    var spendingByMember: [FamilyMemberSpendingSnapshot]
    var incomeByMember: [FamilyMemberSpendingSnapshot]
    var insights: [FamilyInsight]
}

struct FamilyMonthlySpendableSnapshot: Equatable {
    let rawMinor: Int64
    let displayMinor: Int64
    let shortfallMinor: Int64

    var isShortfall: Bool {
        shortfallMinor > 0
    }
}

enum FamilyLogic {
    static func monthlySpendable(
        totalAssetsMinor: Int64,
        monthlyDueMinor: Int64
    ) -> FamilyMonthlySpendableSnapshot {
        let normalizedMonthlyDueMinor = max(monthlyDueMinor, 0)
        let rawMinor = totalAssetsMinor - normalizedMonthlyDueMinor

        return FamilyMonthlySpendableSnapshot(
            rawMinor: rawMinor,
            displayMinor: max(rawMinor, 0),
            shortfallMinor: max(-rawMinor, 0)
        )
    }

    static func access(
        viewerRole: FamilyRole,
        viewerPolicy: FamilyPermissionPolicy,
        targetRole: FamilyRole,
        isSameUser: Bool
    ) -> FamilyMemberAccessCapabilities {
        if isSameUser {
            return FamilyMemberAccessCapabilities(
                canOpenFamilyHome: viewerPolicy.canViewFamilyDashboard,
                canInviteMembers: viewerRole == .owner,
                canManageMembers: viewerRole == .owner,
                canViewTarget: true,
                canEditTarget: true,
                canViewTargetWallets: true,
                canViewTargetDebts: true
            )
        }

        if viewerRole == .owner {
            return FamilyMemberAccessCapabilities(
                canOpenFamilyHome: true,
                canInviteMembers: true,
                canManageMembers: true,
                canViewTarget: true,
                canEditTarget: viewerPolicy.canEditOthers && (targetRole != .kid || viewerPolicy.canEditKids),
                canViewTargetWallets: true,
                canViewTargetDebts: true
            )
        }

        let targetIsKid = targetRole == .kid
        let canViewTarget = viewerPolicy.canViewOthers && (!targetIsKid || viewerPolicy.canViewKids)
        let canEditTarget = viewerPolicy.canEditOthers && (!targetIsKid || viewerPolicy.canEditKids)

        return FamilyMemberAccessCapabilities(
            canOpenFamilyHome: viewerPolicy.canViewFamilyDashboard,
            canInviteMembers: viewerRole == .owner,
            canManageMembers: viewerRole == .owner,
            canViewTarget: canViewTarget,
            canEditTarget: canEditTarget,
            canViewTargetWallets: canViewTarget && viewerPolicy.canViewWallets,
            canViewTargetDebts: canViewTarget && viewerPolicy.canViewDebts
        )
    }

    static func aggregateSummary(
        wallets: [FamilyAggregateWalletSnapshot],
        transactions: [FamilyAggregateTransactionSnapshot],
        selectedInterval: DateInterval,
        visibleMemberIDs: Set<UUID>? = nil,
        memberNames: [UUID: String] = [:],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> FamilyAggregateSummary {
        let visibleWallets = wallets.filter { visibleMemberIDs?.contains($0.ownerUserID) ?? true }
        let intervalTransactions = transactions.filter {
            (visibleMemberIDs?.contains($0.ownerUserID) ?? true) && selectedInterval.contains($0.occurredAt)
        }

        // 1. Current Balances
        let totalAssetsMinor = visibleWallets.reduce(into: Int64.zero) { partial, wallet in
            partial += max(wallet.balanceMinor, 0)
        }
        let totalDebtMinor = visibleWallets.reduce(into: Int64.zero) { partial, wallet in
            partial += wallet.debtMinor
        }
        let spendableMinor = totalAssetsMinor - totalDebtMinor

        // 2. Trend (Last 7 Days)
        let assetTrend = (0..<7).map { dayOffset -> FamilyTrendPoint in
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayOffset, to: referenceDate) ?? referenceDate)
            // For a simple trend based on current data without full history, 
            // we'd need all transactions to roll back. 
            // For now, let's calculate the "Net worth" at each day by rolling back from current.
            let transactionsAfterDate = transactions.filter {
                (visibleMemberIDs?.contains($0.ownerUserID) ?? true) && $0.occurredAt >= date
            }
            
            // Asset = CurrentAsset - Sum(Income after date) + Sum(Expense after date)
            // This is a simplification.
            let incomeAfter = transactionsAfterDate.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountMinor }
            let expenseAfter = transactionsAfterDate.filter(isExpenseSpending).reduce(0) { $0 + $1.amountMinor }
            
            let historicalSpendable = spendableMinor - incomeAfter + expenseAfter
            return FamilyTrendPoint(date: date, valueMinor: historicalSpendable)
        }
        let reversedTrend = Array(assetTrend.reversed())

        // 3. Distribution
        let balanceByWalletKind = visibleWallets.reduce(into: [FamilyAggregateWalletSnapshot.Kind: Int64]()) {
            partial, wallet in
            partial[wallet.kind, default: 0] += wallet.balanceMinor - wallet.debtMinor
        }

        let expenseMap = intervalTransactions.reduce(into: [String: Int64]()) { partial, transaction in
            guard isExpenseSpending(transaction) else { return }
            partial[transaction.categoryName ?? "Other", default: 0] += transaction.amountMinor
        }
        let expenseByCategory = expenseMap.map { FamilyDonutSegment(label: $0.key, valueMinor: $0.value, colorHex: nil) }
            .sorted { $0.valueMinor > $1.valueMinor }

        // 4. Member Comparison
        let memberSpendingMap = intervalTransactions.reduce(into: [UUID: Int64]()) { partial, transaction in
            guard isExpenseSpending(transaction) else { return }
            partial[transaction.ownerUserID, default: 0] += transaction.amountMinor
        }
        let spendingByMember = memberSpendingMap.map { 
            FamilyMemberSpendingSnapshot(userID: $0.key, name: memberNames[$0.key] ?? "Unknown", amountMinor: $0.value)
        }.sorted { $0.amountMinor > $1.amountMinor }

        let memberIncomeMap = intervalTransactions.reduce(into: [UUID: Int64]()) { partial, transaction in
            guard transaction.kind == .income else { return }
            partial[transaction.ownerUserID, default: 0] += transaction.amountMinor
        }
        let incomeByMember = memberIncomeMap.map { 
            FamilyMemberSpendingSnapshot(userID: $0.key, name: memberNames[$0.key] ?? "Unknown", amountMinor: $0.value)
        }.sorted { $0.amountMinor > $1.amountMinor }

        // 5. Insights
        var insights: [FamilyInsight] = []
        
        // Spending trend vs Previous Interval
        let intervalDuration = selectedInterval.duration
        let previousInterval = DateInterval(
            start: selectedInterval.start.addingTimeInterval(-intervalDuration),
            end: selectedInterval.start
        )
        let previousTransactions = transactions.filter {
            (visibleMemberIDs?.contains($0.ownerUserID) ?? true) && previousInterval.contains($0.occurredAt)
        }
        let currentSpending = intervalTransactions.filter(isExpenseSpending).reduce(0) { $0 + $1.amountMinor }
        let previousSpending = previousTransactions.filter(isExpenseSpending).reduce(0) { $0 + $1.amountMinor }
        
        if previousSpending > 0 {
            let diff = Double(currentSpending - previousSpending) / Double(previousSpending)
            let percent = Int(abs(diff * 100))
            
            let timeframeLabel: String
            if intervalDuration > 3600 * 24 * 300 { // Year
                timeframeLabel = mistiaLocalized(vi: "năm trước", en: "last year", ja: "昨年")
            } else if intervalDuration > 3600 * 24 * 20 { // Month
                timeframeLabel = mistiaLocalized(vi: "tháng trước", en: "last month", ja: "先月")
            } else { // Week
                timeframeLabel = mistiaLocalized(vi: "tuần trước", en: "last week", ja: "先週")
            }

            if diff > 0.1 {
                insights.append(FamilyInsight(
                    text: mistiaLocalized(vi: "Chi tiêu tăng \(percent)% so với \(timeframeLabel)", en: "Spending increased by \(percent)% vs \(timeframeLabel)", ja: "支出が\(timeframeLabel)より \(percent)% 増加しました"),
                    isPositive: false
                ))
            } else if diff < -0.1 {
                insights.append(FamilyInsight(
                    text: mistiaLocalized(vi: "Chi tiêu giảm \(percent)% so với \(timeframeLabel)", en: "Spending decreased by \(percent)% vs \(timeframeLabel)", ja: "支出が\(timeframeLabel)より \(percent)% 減少しました"),
                    isPositive: true
                ))
            }
        }
        
        // Member comparison insight
        if let topSpender = spendingByMember.first, spendingByMember.count > 1 {
            let totalSpending = spendingByMember.reduce(0) { $0 + $1.amountMinor }
            if totalSpending > 0 {
                let ratio = Double(topSpender.amountMinor) / Double(totalSpending)
                if ratio > 0.6 {
                    insights.append(FamilyInsight(
                        text: mistiaLocalized(vi: "\(topSpender.name) đang chi tiêu nhiều nhất (\(Int(ratio*100))%)", en: "\(topSpender.name) is spending the most (\(Int(ratio*100))%)", ja: "\(topSpender.name) が最も支出しています (\(Int(ratio*100))%)"),
                        isPositive: false
                    ))
                }
            }
        }

        return FamilyAggregateSummary(
            totalAssetsMinor: totalAssetsMinor,
            totalDebtMinor: totalDebtMinor,
            spendableMinor: spendableMinor,
            assetTrend: reversedTrend,
            balanceByWalletKind: balanceByWalletKind,
            expenseByCategory: expenseByCategory,
            spendingByMember: spendingByMember,
            incomeByMember: incomeByMember,
            insights: insights
        )
    }

    nonisolated private static func isExpenseSpending(_ transaction: FamilyAggregateTransactionSnapshot) -> Bool {
        transaction.kind == .expense && !transaction.isCreditCardPayment
    }
}
