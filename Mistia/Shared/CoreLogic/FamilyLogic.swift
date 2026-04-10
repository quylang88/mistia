import Foundation

enum FamilyRole: String, CaseIterable, Codable, Hashable {
    case owner
    case viewer
    case editor
    case kid
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
                canEditOthers: true,
                canViewWallets: true,
                canViewDebts: true,
                canViewKids: true,
                canEditKids: true
            )
        case .viewer:
            FamilyPermissionPolicy(
                canViewFamilyDashboard: true,
                canViewOthers: false,
                canEditOthers: false,
                canViewWallets: true,
                canViewDebts: true,
                canViewKids: false,
                canEditKids: false
            )
        case .editor:
            FamilyPermissionPolicy(
                canViewFamilyDashboard: true,
                canViewOthers: true,
                canEditOthers: true,
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
}

struct FamilyAggregateSummary: Equatable {
    var totalAssetsMinor: Int64
    var totalDebtMinor: Int64
    var spendableMinor: Int64
    var balanceByWalletKind: [FamilyAggregateWalletSnapshot.Kind: Int64]
    var expenseByCategory: [String: Int64]
    var totalsByMember: [UUID: Int64]
}

enum FamilyLogic {
    static func access(
        viewerRole: FamilyRole,
        viewerPolicy: FamilyPermissionPolicy,
        targetRole: FamilyRole,
        isSameUser: Bool
    ) -> FamilyMemberAccessCapabilities {
        if isSameUser {
            return FamilyMemberAccessCapabilities(
                canOpenFamilyHome: viewerRole != .kid && viewerPolicy.canViewFamilyDashboard,
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
                canEditTarget: true,
                canViewTargetWallets: true,
                canViewTargetDebts: true
            )
        }

        if viewerRole == .kid {
            return .none
        }

        let targetIsKid = targetRole == .kid
        let canViewTarget = viewerPolicy.canViewOthers && (!targetIsKid || viewerPolicy.canViewKids)
        let canEditTarget = viewerPolicy.canEditOthers && (!targetIsKid || viewerPolicy.canEditKids)

        return FamilyMemberAccessCapabilities(
            canOpenFamilyHome: viewerPolicy.canViewFamilyDashboard,
            canInviteMembers: false,
            canManageMembers: false,
            canViewTarget: canViewTarget,
            canEditTarget: canEditTarget,
            canViewTargetWallets: canViewTarget && viewerPolicy.canViewWallets,
            canViewTargetDebts: canViewTarget && viewerPolicy.canViewDebts
        )
    }

    static func aggregateSummary(
        wallets: [FamilyAggregateWalletSnapshot],
        transactions: [FamilyAggregateTransactionSnapshot],
        monthInterval: DateInterval,
        visibleMemberIDs: Set<UUID>? = nil
    ) -> FamilyAggregateSummary {
        let visibleWallets = wallets.filter { visibleMemberIDs?.contains($0.ownerUserID) ?? true }
        let visibleTransactions = transactions.filter {
            (visibleMemberIDs?.contains($0.ownerUserID) ?? true) && monthInterval.contains($0.occurredAt)
        }

        let totalAssetsMinor = visibleWallets.reduce(into: Int64.zero) { partial, wallet in
            partial += max(wallet.balanceMinor, 0)
        }
        let totalDebtMinor = visibleWallets.reduce(into: Int64.zero) { partial, wallet in
            partial += wallet.debtMinor
        }
        let spendableMinor = totalAssetsMinor - totalDebtMinor

        let balanceByWalletKind = visibleWallets.reduce(into: [FamilyAggregateWalletSnapshot.Kind: Int64]()) {
            partial, wallet in
            partial[wallet.kind, default: 0] += wallet.balanceMinor
        }

        let expenseByCategory = visibleTransactions.reduce(into: [String: Int64]()) { partial, transaction in
            guard transaction.kind == .expense else { return }
            partial[transaction.categoryName ?? "Other", default: 0] += transaction.amountMinor
        }

        let totalsByMember = visibleWallets.reduce(into: [UUID: Int64]()) { partial, wallet in
            partial[wallet.ownerUserID, default: 0] += wallet.balanceMinor - wallet.debtMinor
        }

        return FamilyAggregateSummary(
            totalAssetsMinor: totalAssetsMinor,
            totalDebtMinor: totalDebtMinor,
            spendableMinor: spendableMinor,
            balanceByWalletKind: balanceByWalletKind,
            expenseByCategory: expenseByCategory,
            totalsByMember: totalsByMember
        )
    }
}
