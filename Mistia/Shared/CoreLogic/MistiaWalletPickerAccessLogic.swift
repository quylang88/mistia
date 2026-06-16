import Foundation

nonisolated enum MistiaWalletPickerLabelMode: Equatable {
    case contextual
    case alwaysShowsOwner
}

nonisolated struct MistiaWalletPickerWalletSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let ownerUserID: UUID
    let kind: LedgerWalletKind
    let sortOrder: Int
    let createdAt: Date
    let isArchived: Bool
    let deletedAt: Date?

    init(
        id: UUID,
        name: String,
        ownerUserID: UUID,
        kind: LedgerWalletKind,
        sortOrder: Int,
        createdAt: Date,
        isArchived: Bool,
        deletedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.ownerUserID = ownerUserID
        self.kind = kind
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.deletedAt = deletedAt
    }
}

nonisolated struct MistiaWalletPickerAccessContext: Equatable {
    let currentSelfUserID: UUID?
    let targetOwnerUserID: UUID?
    let usableWalletIDs: Set<UUID>
    let preferredWalletIDs: Set<UUID>
    let excludesCreditCards: Bool
    let excludedWalletID: UUID?

    init(
        currentSelfUserID: UUID?,
        targetOwnerUserID: UUID?,
        usableWalletIDs: Set<UUID> = [],
        preferredWalletIDs: Set<UUID> = [],
        excludesCreditCards: Bool = false,
        excludedWalletID: UUID? = nil
    ) {
        self.currentSelfUserID = currentSelfUserID
        self.targetOwnerUserID = targetOwnerUserID
        self.usableWalletIDs = usableWalletIDs
        self.preferredWalletIDs = preferredWalletIDs
        self.excludesCreditCards = excludesCreditCards
        self.excludedWalletID = excludedWalletID
    }
}

nonisolated enum MistiaWalletPickerAccessLogic {
    static func availableWallets(
        from wallets: [MistiaWalletPickerWalletSnapshot],
        context: MistiaWalletPickerAccessContext
    ) -> [MistiaWalletPickerWalletSnapshot] {
        let targetOwnerUserID = context.targetOwnerUserID ?? context.currentSelfUserID

        return wallets
            .filter { wallet in
                guard wallet.id != context.excludedWalletID else {
                    return false
                }
                guard let targetOwnerUserID, wallet.ownerUserID == targetOwnerUserID else {
                    return false
                }
                guard canUse(wallet, currentSelfUserID: context.currentSelfUserID, usableWalletIDs: context.usableWalletIDs) else {
                    return false
                }

                let isPreferred = context.preferredWalletIDs.contains(wallet.id)
                if context.excludesCreditCards && wallet.kind == .creditCard && !isPreferred {
                    return false
                }
                return (wallet.deletedAt == nil && !wallet.isArchived) || isPreferred
            }
            .sorted(by: walletSort)
    }

    static func title(
        for wallet: MistiaWalletPickerWalletSnapshot,
        currentSelfUserID: UUID?,
        memberDisplayNames: [UUID: String],
        labelMode: MistiaWalletPickerLabelMode
    ) -> String {
        if labelMode == .contextual && wallet.ownerUserID == currentSelfUserID {
            return wallet.name
        }

        let ownerName = memberDisplayNames[wallet.ownerUserID]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ownerName, !ownerName.isEmpty else {
            return wallet.name
        }
        return "\(wallet.name) • \(ownerName)"
    }

    private static func canUse(
        _ wallet: MistiaWalletPickerWalletSnapshot,
        currentSelfUserID: UUID?,
        usableWalletIDs: Set<UUID>
    ) -> Bool {
        wallet.ownerUserID == currentSelfUserID || usableWalletIDs.contains(wallet.id)
    }

    private static func walletSort(
        _ lhs: MistiaWalletPickerWalletSnapshot,
        _ rhs: MistiaWalletPickerWalletSnapshot
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.createdAt < rhs.createdAt
    }
}
