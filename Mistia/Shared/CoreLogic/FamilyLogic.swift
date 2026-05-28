import Foundation

struct FamilyMemberViewingToolbarPresentation: Equatable {
    let displayName: String
    let initials: String
    let exitTitle: String
    let exitMessage: String
    let confirmExitTitle: String
    let cancelTitle: String
    let accessibilityLabel: String
}

enum FamilyMemberViewingToolbarLogic {
    static let privateEmailPlaceholder = "***"

    static func presentation(displayName: String) -> FamilyMemberViewingToolbarPresentation {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = normalizedName.isEmpty
            ? L10n.shared.family.familycontext.aFamilyMember
            : normalizedName

        return FamilyMemberViewingToolbarPresentation(
            displayName: resolvedName,
            initials: String(resolvedName.prefix(2)).uppercased(),
            exitTitle: L10n.shared.family.memberViewing.exitTitle,
            exitMessage: L10n.shared.family.memberViewing.exitMessage(resolvedName),
            confirmExitTitle: L10n.shared.family.memberViewing.confirmExit,
            cancelTitle: L10n.common.cancel,
            accessibilityLabel: L10n.shared.family.memberViewing.avatarAccessibility(resolvedName)
        )
    }

    static func maskedEmail(_ email: String?) -> String {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let atIndex = trimmedEmail.firstIndex(of: "@") else {
            return privateEmailPlaceholder
        }

        let domainStartIndex = trimmedEmail.index(after: atIndex)
        guard domainStartIndex < trimmedEmail.endIndex else {
            return privateEmailPlaceholder
        }

        return "\(privateEmailPlaceholder)@\(trimmedEmail[domainStartIndex...])"
    }
}

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

nonisolated struct FamilyAggregateWalletSnapshot: Equatable {
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
    let name: String?
    let currencyCode: String

    init(
        ownerUserID: UUID,
        kind: Kind,
        balanceMinor: Int64,
        debtMinor: Int64,
        name: String? = nil,
        currencyCode: String = "JPY"
    ) {
        self.ownerUserID = ownerUserID
        self.kind = kind
        self.balanceMinor = balanceMinor
        self.debtMinor = debtMinor
        self.name = name
        self.currencyCode = currencyCode
    }
}

nonisolated struct FamilyWalletAggregateSnapshot: Equatable, Identifiable {
    let id: String
    let ownerUserID: UUID
    let name: String
    let kind: LedgerWalletKind
    let currentBalanceMinor: Int64
    let debtMinor: Int64
    let currencyCode: String
    let sortOrder: Int
    let createdAt: Date
}

nonisolated struct FamilyBudgetPlanSnapshot: Equatable, Identifiable {
    let id: UUID
    let ownerUserID: UUID
    let categoryName: String
    let iconSymbolName: String
    let colorHex: String
    let limitMinor: Int64
    let currencyCode: String
    let monthAnchor: Date
}

nonisolated struct FamilyBudgetAggregateSnapshot: Equatable, Identifiable {
    let id: String
    let sourceBudgetID: UUID
    let sourceOwnerUserID: UUID
    let name: String
    let iconSymbolName: String
    let colorHex: String
    let spentMinor: Int64
    let limitMinor: Int64
    let currencyCode: String
    let daysRemaining: Int

    nonisolated var progress: Double {
        guard limitMinor > 0 else { return 0 }
        return Double(spentMinor) / Double(limitMinor)
    }

    nonisolated var progressPercentText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

nonisolated struct FamilyGoalSnapshot: Equatable, Identifiable {
    let id: UUID
    let ownerUserID: UUID
    let name: String
    let iconSymbolName: String
    let targetMinor: Int64
    let currentSavedMinor: Int64
    let targetDate: Date
    let currencyCode: String
    let sortOrder: Int
}

nonisolated struct FamilyGoalAggregateSnapshot: Equatable, Identifiable {
    let id: String
    let sourceGoalID: UUID
    let sourceOwnerUserID: UUID
    let name: String
    let iconSymbolName: String
    let targetMinor: Int64
    let currentSavedMinor: Int64
    let targetDate: Date
    let currencyCode: String

    nonisolated var progress: Double {
        guard targetMinor > 0 else { return 0 }
        return Double(currentSavedMinor) / Double(targetMinor)
    }

    nonisolated var progressPercentText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

nonisolated struct FamilyAggregateTransactionSnapshot: Equatable {
    enum Kind: String, Equatable {
        case expense
        case income
        case transfer
    }

    let ownerUserID: UUID
    let createdByUserID: UUID?
    let categoryName: String?
    let categoryParentName: String?
    let occurredAt: Date
    let kind: Kind
    let amountMinor: Int64
    let currencyCode: String
    let isCreditCardPayment: Bool
    let isAdjustment: Bool
    let isInstallmentPayment: Bool

    init(
        ownerUserID: UUID,
        createdByUserID: UUID? = nil,
        categoryName: String?,
        categoryParentName: String? = nil,
        occurredAt: Date,
        kind: Kind,
        amountMinor: Int64,
        currencyCode: String = "JPY",
        isCreditCardPayment: Bool = false,
        isAdjustment: Bool = false,
        isInstallmentPayment: Bool = false
    ) {
        self.ownerUserID = ownerUserID
        self.createdByUserID = createdByUserID
        self.categoryName = categoryName
        self.categoryParentName = categoryParentName
        self.occurredAt = occurredAt
        self.kind = kind
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.isCreditCardPayment = isCreditCardPayment
        self.isAdjustment = isAdjustment
        self.isInstallmentPayment = isInstallmentPayment
    }
}

nonisolated struct FamilyTrendPoint: Equatable, Identifiable {
    let date: Date
    let valueMinor: Int64
    var id: Date { date }
}

nonisolated struct FamilyMemberSpendingSnapshot: Equatable, Identifiable {
    let userID: UUID
    let name: String
    let amountMinor: Int64
    var id: UUID { userID }
}

nonisolated struct FamilyDonutSegment: Equatable, Identifiable {
    let label: String
    let valueMinor: Int64
    let colorHex: String?
    var id: String { label }
}

nonisolated struct FamilyInsight: Equatable {
    let text: String
    let isPositive: Bool
}

nonisolated struct FamilyAggregateSummary: Equatable {
    var totalAssetsMinor: Int64
    var totalDebtMinor: Int64
    var spendableMinor: Int64
    var assetTrend: [FamilyTrendPoint]
    var balanceByWalletKind: [FamilyAggregateWalletSnapshot.Kind: Int64]
    var balanceByWalletName: [FamilyDonutSegment]
    var expenseByCategory: [FamilyDonutSegment]
    var spendingByMember: [FamilyMemberSpendingSnapshot]
    var incomeByMember: [FamilyMemberSpendingSnapshot]
    var insights: [FamilyInsight]
}

nonisolated struct FamilyMonthlySpendableSnapshot: Equatable {
    let rawMinor: Int64
    let displayMinor: Int64
    let shortfallMinor: Int64

    var isShortfall: Bool {
        shortfallMinor > 0
    }
}

nonisolated enum FamilyLogic {
    nonisolated static func normalizedFamilyGroupingName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    nonisolated static func aggregateWalletsByName(
        _ wallets: [FamilyWalletAggregateSnapshot],
        reportingCurrencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = []
    ) -> [FamilyWalletAggregateSnapshot] {
        Dictionary(grouping: wallets) { wallet in
            normalizedFamilyGroupingName(wallet.name)
        }
        .compactMap { key, groupedWallets in
            guard !key.isEmpty,
                  let representative = groupedWallets.sorted(by: walletAggregateSort).first else {
                return nil
            }

            let groupedCurrencyCodes = Set(groupedWallets.map { MistiaCurrencyLogic.normalizedCode($0.currencyCode) })
            let outputCurrencyCode = groupedCurrencyCodes.count == 1
                ? MistiaCurrencyLogic.normalizedCode(representative.currencyCode)
                : MistiaCurrencyLogic.normalizedCode(reportingCurrencyCode)

            let currentBalance = groupedWallets.reduce(into: Int64.zero) { partial, wallet in
                partial += reportingAmount(
                    amountMinor: wallet.currentBalanceMinor,
                    sourceCurrencyCode: wallet.currencyCode,
                    currencyCode: outputCurrencyCode,
                    exchangeRates: exchangeRates
                )
            }
            let debt = groupedWallets.reduce(into: Int64.zero) { partial, wallet in
                partial += reportingAmount(
                    amountMinor: wallet.debtMinor,
                    sourceCurrencyCode: wallet.currencyCode,
                    currencyCode: outputCurrencyCode,
                    exchangeRates: exchangeRates
                )
            }

            return FamilyWalletAggregateSnapshot(
                id: "wallet-name-\(key)",
                ownerUserID: representative.ownerUserID,
                name: representative.name,
                kind: representative.kind,
                currentBalanceMinor: currentBalance,
                debtMinor: debt,
                currencyCode: outputCurrencyCode,
                sortOrder: representative.sortOrder,
                createdAt: representative.createdAt
            )
        }
        .sorted(by: walletAggregateSort)
    }

    nonisolated static func familyBudgetRows(
        plans: [FamilyBudgetPlanSnapshot],
        transactions: [FamilyAggregateTransactionSnapshot],
        selectedMonth: Date,
        ownerUserID: UUID?,
        budgetManagerUserID: UUID?,
        memberOrder: [UUID],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current,
        exchangeRates: [MistiaExchangeRate] = [],
        minimumProgress: Double = 0.5,
        includesMinimumProgress: Bool = false,
        maximumCount: Int? = 3
    ) -> [FamilyBudgetAggregateSnapshot] {
        let monthStart = PlanningLogic.startOfMonth(for: selectedMonth, calendar: calendar)
        let monthInterval = calendar.dateInterval(of: .month, for: monthStart)
        let groupedPlans = Dictionary(grouping: plans.filter { plan in
            !normalizedFamilyGroupingName(plan.categoryName).isEmpty
                && PlanningLogic.startOfMonth(for: plan.monthAnchor, calendar: calendar) == monthStart
        }) { plan in
            normalizedFamilyGroupingName(plan.categoryName)
        }

        let daysRemaining = daysRemainingInMonth(
            for: monthStart,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let rows = groupedPlans.compactMap { key, groupedPlans -> FamilyBudgetAggregateSnapshot? in
            guard let selectedPlan = prioritizedPlan(
                groupedPlans,
                ownerUserID: ownerUserID,
                managerUserID: budgetManagerUserID,
                memberOrder: memberOrder
            ) else {
                return nil
            }

            let spent = transactions.reduce(into: Int64.zero) { partial, transaction in
                guard isExpenseSpending(transaction),
                      monthInterval.map({ transaction.occurredAt >= $0.start && transaction.occurredAt < $0.end }) == true,
                      transaction.matchesCategoryGroupingKey(key)
                else {
                    return
                }

                partial += reportingAmount(
                    amountMinor: transaction.amountMinor,
                    sourceCurrencyCode: transaction.currencyCode,
                    currencyCode: selectedPlan.currencyCode,
                    exchangeRates: exchangeRates
                )
            }

            return FamilyBudgetAggregateSnapshot(
                id: "budget-category-\(key)",
                sourceBudgetID: selectedPlan.id,
                sourceOwnerUserID: selectedPlan.ownerUserID,
                name: selectedPlan.categoryName,
                iconSymbolName: selectedPlan.iconSymbolName,
                colorHex: selectedPlan.colorHex,
                spentMinor: spent,
                limitMinor: selectedPlan.limitMinor,
                currencyCode: selectedPlan.currencyCode,
                daysRemaining: daysRemaining
            )
        }

        let sortedRows = rows
            .filter { row in
                includesMinimumProgress
                    ? row.progress >= minimumProgress
                    : row.progress > minimumProgress
            }
            .sorted { lhs, rhs in
                if lhs.progress != rhs.progress {
                    return lhs.progress > rhs.progress
                }
                if lhs.daysRemaining != rhs.daysRemaining {
                    return lhs.daysRemaining < rhs.daysRemaining
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return maximumCount.map { Array(sortedRows.prefix($0)) } ?? sortedRows
    }

    nonisolated static func familyGoalRows(
        goals: [FamilyGoalSnapshot],
        ownerUserID: UUID?,
        goalManagerUserID: UUID?,
        memberOrder: [UUID],
        exchangeRates: [MistiaExchangeRate] = []
    ) -> [FamilyGoalAggregateSnapshot] {
        Dictionary(grouping: goals.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { goal in
            normalizedFamilyGroupingName(goal.name)
        }
        .compactMap { key, groupedGoals -> FamilyGoalAggregateSnapshot? in
            guard let selectedGoal = prioritizedGoal(
                groupedGoals,
                ownerUserID: ownerUserID,
                managerUserID: goalManagerUserID,
                memberOrder: memberOrder
            ) else {
                return nil
            }

            let saved = groupedGoals.reduce(into: Int64.zero) { partial, goal in
                partial += reportingAmount(
                    amountMinor: goal.currentSavedMinor,
                    sourceCurrencyCode: goal.currencyCode,
                    currencyCode: selectedGoal.currencyCode,
                    exchangeRates: exchangeRates
                )
            }

            return FamilyGoalAggregateSnapshot(
                id: "goal-name-\(key)",
                sourceGoalID: selectedGoal.id,
                sourceOwnerUserID: selectedGoal.ownerUserID,
                name: selectedGoal.name,
                iconSymbolName: selectedGoal.iconSymbolName,
                targetMinor: selectedGoal.targetMinor,
                currentSavedMinor: saved,
                targetDate: selectedGoal.targetDate,
                currencyCode: selectedGoal.currencyCode
            )
        }
        .sorted { lhs, rhs in
            if lhs.progress != rhs.progress {
                return lhs.progress > rhs.progress
            }
            if lhs.targetDate != rhs.targetDate {
                return lhs.targetDate < rhs.targetDate
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

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
        reportingCurrencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = [],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> FamilyAggregateSummary {
        let visibleWallets = wallets.filter { visibleMemberIDs?.contains($0.ownerUserID) ?? true }
        let intervalTransactions = transactions.filter {
            (visibleMemberIDs?.contains($0.ownerUserID) ?? true) && selectedInterval.contains($0.occurredAt)
        }
        let summaryCurrencyCode = MistiaCurrencyLogic.normalizedCode(reportingCurrencyCode)

        // 1. Current Balances
        let totalAssetsMinor = visibleWallets.reduce(into: Int64.zero) { partial, wallet in
            partial += max(
                reportingAmount(
                    amountMinor: wallet.balanceMinor,
                    sourceCurrencyCode: wallet.currencyCode,
                    currencyCode: summaryCurrencyCode,
                    exchangeRates: exchangeRates
                ),
                0
            )
        }
        let totalDebtMinor = visibleWallets.reduce(into: Int64.zero) { partial, wallet in
            partial += reportingAmount(
                amountMinor: wallet.debtMinor,
                sourceCurrencyCode: wallet.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
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
            let incomeAfter = transactionsAfterDate.filter { $0.kind == .income }.reduce(0) { partial, transaction in
                partial + reportingAmount(
                    amountMinor: transaction.amountMinor,
                    sourceCurrencyCode: transaction.currencyCode,
                    currencyCode: summaryCurrencyCode,
                    exchangeRates: exchangeRates
                )
            }
            let expenseAfter = transactionsAfterDate.filter(isExpenseSpending).reduce(0) { partial, transaction in
                partial + reportingAmount(
                    amountMinor: transaction.amountMinor,
                    sourceCurrencyCode: transaction.currencyCode,
                    currencyCode: summaryCurrencyCode,
                    exchangeRates: exchangeRates
                )
            }
            
            let historicalSpendable = spendableMinor - incomeAfter + expenseAfter
            return FamilyTrendPoint(date: date, valueMinor: historicalSpendable)
        }
        let reversedTrend = Array(assetTrend.reversed())

        // 3. Distribution
        let balanceByWalletKind = visibleWallets.reduce(into: [FamilyAggregateWalletSnapshot.Kind: Int64]()) {
            partial, wallet in
            let balance = reportingAmount(
                amountMinor: wallet.balanceMinor,
                sourceCurrencyCode: wallet.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
            let debt = reportingAmount(
                amountMinor: wallet.debtMinor,
                sourceCurrencyCode: wallet.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
            partial[wallet.kind, default: 0] += balance - debt
        }

        let balanceByWalletNameMap = visibleWallets.reduce(into: [String: (name: String, value: Int64)]()) { partial, wallet in
            guard let name = wallet.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                return
            }
            let key = normalizedFamilyGroupingName(name)
            let current = partial[key] ?? (name: name, value: 0)
            let balance = reportingAmount(
                amountMinor: wallet.balanceMinor,
                sourceCurrencyCode: wallet.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
            let debt = reportingAmount(
                amountMinor: wallet.debtMinor,
                sourceCurrencyCode: wallet.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
            partial[key] = (name: current.name, value: current.value + balance - debt)
        }
        let balanceByWalletName = balanceByWalletNameMap
            .map { key, value in
                FamilyDonutSegment(label: value.name, valueMinor: value.value, colorHex: nil)
            }
            .sorted { lhs, rhs in
                if lhs.valueMinor != rhs.valueMinor {
                    return lhs.valueMinor > rhs.valueMinor
                }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }

        let expenseMap = intervalTransactions.reduce(into: [String: Int64]()) { partial, transaction in
            guard isExpenseSpending(transaction) else { return }
            partial[transaction.categoryName ?? "Other", default: 0] += reportingAmount(
                amountMinor: transaction.amountMinor,
                sourceCurrencyCode: transaction.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
        }
        let expenseByCategory = expenseMap.map { FamilyDonutSegment(label: $0.key, valueMinor: $0.value, colorHex: nil) }
            .sorted { $0.valueMinor > $1.valueMinor }

        // 4. Member Comparison
        let memberSpendingMap = intervalTransactions.reduce(into: [UUID: Int64]()) { partial, transaction in
            guard isExpenseSpending(transaction) else { return }
            let spendingUserID = transaction.createdByUserID ?? transaction.ownerUserID
            guard visibleMemberIDs?.contains(spendingUserID) ?? true else { return }
            partial[spendingUserID, default: 0] += reportingAmount(
                amountMinor: transaction.amountMinor,
                sourceCurrencyCode: transaction.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
        }
        let spendingByMember = memberSpendingMap.map { 
            FamilyMemberSpendingSnapshot(userID: $0.key, name: memberNames[$0.key] ?? "Unknown", amountMinor: $0.value)
        }.sorted { $0.amountMinor > $1.amountMinor }

        let memberIncomeMap = intervalTransactions.reduce(into: [UUID: Int64]()) { partial, transaction in
            guard transaction.kind == .income else { return }
            partial[transaction.ownerUserID, default: 0] += reportingAmount(
                amountMinor: transaction.amountMinor,
                sourceCurrencyCode: transaction.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
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
        let currentSpending = intervalTransactions.filter(isExpenseSpending).reduce(0) { partial, transaction in
            partial + reportingAmount(
                amountMinor: transaction.amountMinor,
                sourceCurrencyCode: transaction.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
        }
        let previousSpending = previousTransactions.filter(isExpenseSpending).reduce(0) { partial, transaction in
            partial + reportingAmount(
                amountMinor: transaction.amountMinor,
                sourceCurrencyCode: transaction.currencyCode,
                currencyCode: summaryCurrencyCode,
                exchangeRates: exchangeRates
            )
        }
        
        if previousSpending > 0 {
            let diff = Double(currentSpending - previousSpending) / Double(previousSpending)
            let percent = Int(abs(diff * 100))
            
            let timeframeLabel: String
            if intervalDuration > 3600 * 24 * 300 { // Year
                timeframeLabel = L10n.shared.corelogic.family.lastYear
            } else if intervalDuration > 3600 * 24 * 20 { // Month
                timeframeLabel = L10n.shared.corelogic.family.lastMonth
            } else { // Week
                timeframeLabel = L10n.shared.corelogic.family.lastWeek
            }

            if diff > 0.1 {
                insights.append(FamilyInsight(
                    text: L10n.shared.corelogic.family.spendingIncreasedByValueVsValue(String(describing: percent), String(describing: timeframeLabel)),
                    isPositive: false
                ))
            } else if diff < -0.1 {
                insights.append(FamilyInsight(
                    text: L10n.shared.corelogic.family.spendingDecreasedByValueVsValue(String(describing: percent), String(describing: timeframeLabel)),
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
                        text: L10n.shared.corelogic.family.valueIsSpendingTheMostValue(String(describing: topSpender.name), String(describing: Int(ratio*100))),
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
            balanceByWalletName: balanceByWalletName,
            expenseByCategory: expenseByCategory,
            spendingByMember: spendingByMember,
            incomeByMember: incomeByMember,
            insights: insights
        )
    }

    nonisolated private static func isExpenseSpending(_ transaction: FamilyAggregateTransactionSnapshot) -> Bool {
        transaction.kind == .expense
            && !transaction.isAdjustment
            && !transaction.isCreditCardPayment
            && !transaction.isInstallmentPayment
    }

    nonisolated private static func reportingAmount(
        amountMinor: Int64,
        sourceCurrencyCode: String,
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate]
    ) -> Int64 {
        MistiaCurrencyLogic.reportingMinorAmount(
            amountMinor: amountMinor,
            sourceCurrencyCode: sourceCurrencyCode,
            reportingCurrencyCode: currencyCode,
            rates: exchangeRates
        ) ?? 0
    }

    nonisolated private static func walletAggregateSort(
        lhs: FamilyWalletAggregateSnapshot,
        rhs: FamilyWalletAggregateSnapshot
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    nonisolated private static func prioritizedPlan(
        _ plans: [FamilyBudgetPlanSnapshot],
        ownerUserID: UUID?,
        managerUserID: UUID?,
        memberOrder: [UUID]
    ) -> FamilyBudgetPlanSnapshot? {
        prioritizedItem(
            plans,
            ownerUserID: ownerUserID,
            managerUserID: managerUserID,
            memberOrder: memberOrder,
            owner: \.ownerUserID,
            fallbackSort: budgetPlanSort
        )
    }

    nonisolated private static func prioritizedGoal(
        _ goals: [FamilyGoalSnapshot],
        ownerUserID: UUID?,
        managerUserID: UUID?,
        memberOrder: [UUID]
    ) -> FamilyGoalSnapshot? {
        prioritizedItem(
            goals,
            ownerUserID: ownerUserID,
            managerUserID: managerUserID,
            memberOrder: memberOrder,
            owner: \.ownerUserID,
            fallbackSort: goalSort
        )
    }

    nonisolated private static func prioritizedItem<T>(
        _ items: [T],
        ownerUserID: UUID?,
        managerUserID: UUID?,
        memberOrder: [UUID],
        owner: KeyPath<T, UUID>,
        fallbackSort: (T, T) -> Bool
    ) -> T? {
        let sortedItems = items.sorted(by: fallbackSort)
        if let ownerUserID,
           let ownerItem = sortedItems.first(where: { $0[keyPath: owner] == ownerUserID }) {
            return ownerItem
        }
        if let managerUserID,
           let managerItem = sortedItems.first(where: { $0[keyPath: owner] == managerUserID }) {
            return managerItem
        }
        if sortedItems.count == 1 {
            return sortedItems.first
        }
        for memberID in memberOrder {
            if let memberItem = sortedItems.first(where: { $0[keyPath: owner] == memberID }) {
                return memberItem
            }
        }
        return sortedItems.first
    }

    nonisolated private static func budgetPlanSort(
        lhs: FamilyBudgetPlanSnapshot,
        rhs: FamilyBudgetPlanSnapshot
    ) -> Bool {
        if lhs.categoryName.localizedCaseInsensitiveCompare(rhs.categoryName) != .orderedSame {
            return lhs.categoryName.localizedCaseInsensitiveCompare(rhs.categoryName) == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated private static func goalSort(
        lhs: FamilyGoalSnapshot,
        rhs: FamilyGoalSnapshot
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.targetDate != rhs.targetDate {
            return lhs.targetDate < rhs.targetDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated private static func daysRemainingInMonth(
        for selectedMonth: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        let monthStart = PlanningLogic.startOfMonth(for: selectedMonth, calendar: calendar)
        let referenceMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart),
              let monthEnd = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else {
            return 0
        }

        if monthStart < referenceMonth {
            return 0
        }
        if monthStart == referenceMonth {
            let start = calendar.startOfDay(for: referenceDate)
            return max((calendar.dateComponents([.day], from: start, to: monthEnd).day ?? 0) + 1, 0)
        }
        return (calendar.dateComponents([.day], from: monthStart, to: monthEnd).day ?? 0) + 1
    }
}

private extension FamilyAggregateTransactionSnapshot {
    nonisolated func matchesCategoryGroupingKey(_ key: String) -> Bool {
        let categoryKey = categoryName.map(FamilyLogic.normalizedFamilyGroupingName)
        let parentKey = categoryParentName.map(FamilyLogic.normalizedFamilyGroupingName)
        return categoryKey == key || parentKey == key
    }
}
