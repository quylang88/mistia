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

nonisolated enum FamilyRole: CaseIterable, Codable, Hashable, RawRepresentable {
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

nonisolated struct FamilyPermissionPolicy: Codable, Equatable, Hashable {
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
    let creditCardStatementStatus: FamilyCreditCardStatementStatus?

    init(
        id: String,
        ownerUserID: UUID,
        name: String,
        kind: LedgerWalletKind,
        currentBalanceMinor: Int64,
        debtMinor: Int64,
        currencyCode: String,
        sortOrder: Int,
        createdAt: Date,
        creditCardStatementStatus: FamilyCreditCardStatementStatus? = nil
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.name = name
        self.kind = kind
        self.currentBalanceMinor = currentBalanceMinor
        self.debtMinor = debtMinor
        self.currencyCode = currencyCode
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.creditCardStatementStatus = creditCardStatementStatus
    }
}

nonisolated enum FamilyCreditCardStatementStatus: Equatable {
    case upcoming
    case paid
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
}

nonisolated struct FamilyMonthlyBillAggregateSnapshot: Equatable, Identifiable {
    let id: String
    let title: String
    let iconSymbolName: String
    let colorHex: String
    let amountMinor: Int64
    let currencyCode: String
    let sourceCount: Int
    let isPaid: Bool
}

nonisolated struct FamilyMonthlyBillTotalSnapshot: Equatable, Identifiable {
    let currencyCode: String
    let amountMinor: Int64

    var id: String { currencyCode }
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
        let rateIndex = MistiaExchangeRateIndex(rates: exchangeRates)

        return Dictionary(grouping: wallets) { wallet in
            normalizedFamilyGroupingName(wallet.name)
        }
        .compactMap { key, groupedWallets in
            guard !key.isEmpty,
                  let representative = groupedWallets.min(by: walletAggregateSort) else {
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
                    rateIndex: rateIndex
                )
            }
            let debt = groupedWallets.reduce(into: Int64.zero) { partial, wallet in
                partial += reportingAmount(
                    amountMinor: wallet.debtMinor,
                    sourceCurrencyCode: wallet.currencyCode,
                    currencyCode: outputCurrencyCode,
                    rateIndex: rateIndex
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
                createdAt: representative.createdAt,
                creditCardStatementStatus: creditCardStatus(for: groupedWallets)
            )
        }
        .sorted(by: walletAggregateSort)
    }

    nonisolated static func monthlyBillRows(
        bills: [PlanningBillSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        selectedMonth: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> [FamilyMonthlyBillAggregateSnapshot] {
        let dueItems = PlanningLogic.recurringBillDueItems(
            bills: bills,
            occurrences: occurrences,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
        return monthlyBillRows(from: dueItems)
    }

    nonisolated static func monthlyBillRows(
        from dueItems: [PlanningRecurringDueSnapshot]
    ) -> [FamilyMonthlyBillAggregateSnapshot] {
        let validItems = dueItems.filter { item in
            guard item.sourceKind == .recurringBill,
                  let amountMinor = item.amountMinor,
                  amountMinor > 0 else {
                return false
            }
            return true
        }

        return Dictionary(grouping: validItems, by: monthlyBillGroupingKey)
            .compactMap { groupKey, groupedItems -> FamilyMonthlyBillAggregateSnapshot? in
                guard let representative = groupedItems.min(by: monthlyBillSort) else {
                    return nil
                }
                let amount = groupedItems.reduce(into: Int64.zero) { partial, item in
                    partial += item.amountMinor ?? 0
                }
                guard amount > 0 else { return nil }

                return FamilyMonthlyBillAggregateSnapshot(
                    id: "family-bill-\(groupKey.id)",
                    title: monthlyBillTitle(for: representative),
                    iconSymbolName: representative.categoryIconSymbolName
                        ?? representative.categorySystemKey?.iconSymbolName
                        ?? representative.iconSymbolName,
                    colorHex: representative.categoryColorHex
                        ?? representative.categorySystemKey?.iconColorHex
                        ?? "#8A8A8E",
                    amountMinor: amount,
                    currencyCode: groupKey.currencyCode,
                    sourceCount: groupedItems.count,
                    isPaid: groupedItems.allSatisfy { $0.status == .paid }
                )
            }
            .sorted { lhs, rhs in
                if lhs.amountMinor != rhs.amountMinor {
                    return lhs.amountMinor > rhs.amountMinor
                }
                if lhs.currencyCode != rhs.currencyCode {
                    return lhs.currencyCode.localizedCaseInsensitiveCompare(rhs.currencyCode) == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    nonisolated static func monthlyBillTotalsByCurrency(
        from rows: [FamilyMonthlyBillAggregateSnapshot]
    ) -> [FamilyMonthlyBillTotalSnapshot] {
        Dictionary(grouping: rows) { row in
            MistiaCurrencyLogic.normalizedCode(row.currencyCode)
        }
        .compactMap { currencyCode, groupedRows in
            let amount = groupedRows.reduce(into: Int64.zero) { partial, row in
                partial += row.amountMinor
            }
            guard amount > 0 else { return nil }
            return FamilyMonthlyBillTotalSnapshot(currencyCode: currencyCode, amountMinor: amount)
        }
        .sorted { lhs, rhs in
            lhs.currencyCode.localizedCaseInsensitiveCompare(rhs.currencyCode) == .orderedAscending
        }
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
        let spendingTransactionsByCategoryKey = budgetSpendingTransactionsByCategoryKey(
            transactions: transactions,
            monthInterval: monthInterval
        )
        let rateIndex = MistiaExchangeRateIndex(rates: exchangeRates)

        let rows = groupedPlans.compactMap { key, groupedPlans -> FamilyBudgetAggregateSnapshot? in
            guard let selectedPlan = prioritizedPlan(
                groupedPlans,
                ownerUserID: ownerUserID,
                managerUserID: budgetManagerUserID,
                memberOrder: memberOrder
            ) else {
                return nil
            }

            let spent = spendingTransactionsByCategoryKey[key]?.reduce(into: Int64.zero) { partial, transaction in
                partial += reportingAmount(
                    amountMinor: transaction.amountMinor,
                    sourceCurrencyCode: transaction.currencyCode,
                    currencyCode: selectedPlan.currencyCode,
                    rateIndex: rateIndex
                )
            } ?? 0

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
        let rateIndex = MistiaExchangeRateIndex(rates: exchangeRates)

        return Dictionary(grouping: goals.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { goal in
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
                    rateIndex: rateIndex
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
        let summaryCurrencyCode = MistiaCurrencyLogic.normalizedCode(reportingCurrencyCode)
        let rateIndex = MistiaExchangeRateIndex(rates: exchangeRates)

        func isVisibleMember(_ userID: UUID) -> Bool {
            visibleMemberIDs?.contains(userID) ?? true
        }

        var totalAssetsMinor = Int64.zero
        var totalDebtMinor = Int64.zero
        var balanceByWalletKind: [FamilyAggregateWalletSnapshot.Kind: Int64] = [:]
        var balanceByWalletNameMap: [String: (name: String, value: Int64)] = [:]

        for wallet in wallets where isVisibleMember(wallet.ownerUserID) {
            let balance = reportingAmount(
                amountMinor: wallet.balanceMinor,
                sourceCurrencyCode: wallet.currencyCode,
                currencyCode: summaryCurrencyCode,
                rateIndex: rateIndex
            )
            let debt = reportingAmount(
                amountMinor: wallet.debtMinor,
                sourceCurrencyCode: wallet.currencyCode,
                currencyCode: summaryCurrencyCode,
                rateIndex: rateIndex
            )

            totalAssetsMinor += max(balance, 0)
            totalDebtMinor += debt
            balanceByWalletKind[wallet.kind, default: 0] += balance - debt

            guard let name = wallet.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                continue
            }
            let key = normalizedFamilyGroupingName(name)
            let current = balanceByWalletNameMap[key] ?? (name: name, value: 0)
            balanceByWalletNameMap[key] = (name: current.name, value: current.value + balance - debt)
        }

        let spendableMinor = totalAssetsMinor - totalDebtMinor

        let trendDates = (0..<7).map { dayOffset in
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayOffset, to: referenceDate) ?? referenceDate)
        }
        var incomeAfterTrendDate = Array(repeating: Int64.zero, count: trendDates.count)
        var expenseAfterTrendDate = Array(repeating: Int64.zero, count: trendDates.count)
        var expenseByCategoryMap: [String: (label: String, valueMinor: Int64)] = [:]
        var memberSpendingMap: [UUID: Int64] = [:]
        var memberIncomeMap: [UUID: Int64] = [:]

        for transaction in transactions where isVisibleMember(transaction.ownerUserID) {
            let isIncome = transaction.kind == .income
            let isSpending = isExpenseSpending(transaction)
            guard isIncome || isSpending else { continue }

            let amount = reportingAmount(
                amountMinor: transaction.amountMinor,
                sourceCurrencyCode: transaction.currencyCode,
                currencyCode: summaryCurrencyCode,
                rateIndex: rateIndex
            )

            for index in trendDates.indices where transaction.occurredAt >= trendDates[index] {
                if isIncome {
                    incomeAfterTrendDate[index] += amount
                } else {
                    expenseAfterTrendDate[index] += amount
                }
            }

            guard selectedInterval.contains(transaction.occurredAt) else { continue }
            if isSpending {
                let trimmedCategoryName = transaction.categoryName?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let categoryLabel = trimmedCategoryName.isEmpty ? "Other" : trimmedCategoryName
                let categoryKey = normalizedFamilyGroupingName(categoryLabel)
                let current = expenseByCategoryMap[categoryKey] ?? (label: categoryLabel, valueMinor: 0)
                expenseByCategoryMap[categoryKey] = (
                    label: current.label,
                    valueMinor: current.valueMinor + amount
                )

                let spendingUserID = transaction.createdByUserID ?? transaction.ownerUserID
                if isVisibleMember(spendingUserID) {
                    memberSpendingMap[spendingUserID, default: 0] += amount
                }
            } else if isIncome {
                memberIncomeMap[transaction.ownerUserID, default: 0] += amount
            }
        }

        let assetTrend = trendDates.indices.map { index in
            let historicalSpendable = spendableMinor - incomeAfterTrendDate[index] + expenseAfterTrendDate[index]
            return FamilyTrendPoint(date: trendDates[index], valueMinor: historicalSpendable)
        }
        let reversedTrend = Array(assetTrend.reversed())

        let balanceByWalletName = balanceByWalletNameMap
            .map { _, value in
                FamilyDonutSegment(label: value.name, valueMinor: value.value, colorHex: nil)
            }
            .sorted { lhs, rhs in
                if lhs.valueMinor != rhs.valueMinor {
                    return lhs.valueMinor > rhs.valueMinor
                }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }

        let expenseByCategory = expenseByCategoryMap.map { _, value in
            FamilyDonutSegment(label: value.label, valueMinor: value.valueMinor, colorHex: nil)
        }
            .sorted { $0.valueMinor > $1.valueMinor }

        let spendingByMember = memberSpendingMap.map { 
            FamilyMemberSpendingSnapshot(userID: $0.key, name: memberNames[$0.key] ?? "Unknown", amountMinor: $0.value)
        }.sorted { $0.amountMinor > $1.amountMinor }

        let incomeByMember = memberIncomeMap.map { 
            FamilyMemberSpendingSnapshot(userID: $0.key, name: memberNames[$0.key] ?? "Unknown", amountMinor: $0.value)
        }.sorted { $0.amountMinor > $1.amountMinor }

        return FamilyAggregateSummary(
            totalAssetsMinor: totalAssetsMinor,
            totalDebtMinor: totalDebtMinor,
            spendableMinor: spendableMinor,
            assetTrend: reversedTrend,
            balanceByWalletKind: balanceByWalletKind,
            balanceByWalletName: balanceByWalletName,
            expenseByCategory: expenseByCategory,
            spendingByMember: spendingByMember,
            incomeByMember: incomeByMember
        )
    }

    nonisolated private static func isExpenseSpending(_ transaction: FamilyAggregateTransactionSnapshot) -> Bool {
        transaction.kind == .expense
            && !transaction.isAdjustment
            && !transaction.isCreditCardPayment
            && !transaction.isInstallmentPayment
    }

    nonisolated private static func budgetSpendingTransactionsByCategoryKey(
        transactions: [FamilyAggregateTransactionSnapshot],
        monthInterval: DateInterval?
    ) -> [String: [FamilyAggregateTransactionSnapshot]] {
        guard let monthInterval else { return [:] }

        var result: [String: [FamilyAggregateTransactionSnapshot]] = [:]
        for transaction in transactions {
            guard isExpenseSpending(transaction),
                  transaction.occurredAt >= monthInterval.start,
                  transaction.occurredAt < monthInterval.end else {
                continue
            }

            for key in transaction.budgetCategoryGroupingKeys {
                result[key, default: []].append(transaction)
            }
        }

        return result
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

    nonisolated private static func reportingAmount(
        amountMinor: Int64,
        sourceCurrencyCode: String,
        currencyCode: String,
        rateIndex: MistiaExchangeRateIndex
    ) -> Int64 {
        MistiaCurrencyLogic.reportingMinorAmount(
            amountMinor: amountMinor,
            sourceCurrencyCode: sourceCurrencyCode,
            reportingCurrencyCode: currencyCode,
            rateIndex: rateIndex
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

    nonisolated private struct MonthlyBillGroupingKey: Hashable {
        let value: String
        let currencyCode: String

        var id: String { "\(value)-\(currencyCode)" }
    }

    nonisolated private static func monthlyBillGroupingKey(
        for item: PlanningRecurringDueSnapshot
    ) -> MonthlyBillGroupingKey {
        let currencyCode = MistiaCurrencyLogic.normalizedCode(item.currencyCode)
        if let categorySystemKey = item.categorySystemKey {
            return MonthlyBillGroupingKey(
                value: "category-system-\(categorySystemKey.rawValue)",
                currencyCode: currencyCode
            )
        }

        let categoryName = item.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !categoryName.isEmpty {
            return MonthlyBillGroupingKey(
                value: "category-name-\(normalizedFamilyGroupingName(categoryName))",
                currencyCode: currencyCode
            )
        }

        return MonthlyBillGroupingKey(
            value: "bill-name-\(normalizedFamilyGroupingName(item.name))",
            currencyCode: currencyCode
        )
    }

    nonisolated private static func monthlyBillTitle(
        for item: PlanningRecurringDueSnapshot
    ) -> String {
        let categoryName = item.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !categoryName.isEmpty {
            return categoryName
        }

        if let categorySystemKey = item.categorySystemKey {
            return categorySystemKey.title
        }

        return item.name
    }

    nonisolated private static func monthlyBillSort(
        lhs: PlanningRecurringDueSnapshot,
        rhs: PlanningRecurringDueSnapshot
    ) -> Bool {
        if lhs.dueDate != rhs.dueDate {
            return lhs.dueDate < rhs.dueDate
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    nonisolated private static func creditCardStatus(
        for wallets: [FamilyWalletAggregateSnapshot]
    ) -> FamilyCreditCardStatementStatus? {
        let statuses = wallets.compactMap(\.creditCardStatementStatus)
        if statuses.contains(.upcoming) {
            return .upcoming
        }
        if statuses.contains(.paid) {
            return .paid
        }
        return nil
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
    nonisolated var budgetCategoryGroupingKeys: Set<String> {
        var keys = Set<String>()

        if let categoryName {
            let key = FamilyLogic.normalizedFamilyGroupingName(categoryName)
            if !key.isEmpty {
                keys.insert(key)
            }
        }

        if let categoryParentName {
            let key = FamilyLogic.normalizedFamilyGroupingName(categoryParentName)
            if !key.isEmpty {
                keys.insert(key)
            }
        }

        return keys
    }
}
