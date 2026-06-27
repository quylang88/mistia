import Foundation

struct MistiaWalletPickerPreparedWallets {
    fileprivate let snapshots: [MistiaWalletPickerWalletSnapshot]
    fileprivate let walletByID: [UUID: LedgerWallet]
    fileprivate let usableWalletIDs: Set<UUID>
}

struct MistiaWalletPickerAccess {
    let sessionStore: SessionStore
    let familyContextStore: FamilyContextStore
    private let walletOwnerMap: [UUID: UUID]

    init(
        sessionStore: SessionStore,
        familyContextStore: FamilyContextStore,
        ownershipScopes: [OwnedRecordScope]
    ) {
        self.init(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownerMaps: MistiaRecordOwnershipStore.ownerMaps(from: ownershipScopes, entities: [.wallet])
        )
    }

    init(
        sessionStore: SessionStore,
        familyContextStore: FamilyContextStore,
        ownerMaps: MistiaRecordOwnerMaps
    ) {
        self.sessionStore = sessionStore
        self.familyContextStore = familyContextStore
        self.walletOwnerMap = ownerMaps[.wallet]
    }

    var currentSelfUserID: UUID? {
        sessionStore.activeLocalProfileUserID
            ?? familyContextStore.currentUserID
            ?? sessionStore.signedInUserID
    }

    func availableWallets(
        from wallets: [LedgerWallet],
        preferredWalletIDs: Set<UUID> = [],
        targetOwnerUserID: UUID?,
        excludesCreditCards: Bool = false,
        excludedWalletID: UUID? = nil
    ) -> [LedgerWallet] {
        availableWallets(
            from: preparedWallets(from: wallets),
            preferredWalletIDs: preferredWalletIDs,
            targetOwnerUserID: targetOwnerUserID,
            excludesCreditCards: excludesCreditCards,
            excludedWalletID: excludedWalletID
        )
    }

    func preparedWallets(from wallets: [LedgerWallet]) -> MistiaWalletPickerPreparedWallets {
        let snapshots = walletSnapshots(from: wallets)
        return MistiaWalletPickerPreparedWallets(
            snapshots: snapshots,
            walletByID: Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) }),
            usableWalletIDs: Set(
                snapshots
                    .filter { snapshot in
                        snapshot.ownerUserID == currentSelfUserID
                            || familyContextStore.canUseWallet(walletID: snapshot.id, ownerUserID: snapshot.ownerUserID)
                    }
                    .map(\.id)
            )
        )
    }

    func availableWallets(
        from preparedWallets: MistiaWalletPickerPreparedWallets,
        preferredWalletIDs: Set<UUID> = [],
        targetOwnerUserID: UUID?,
        excludesCreditCards: Bool = false,
        excludedWalletID: UUID? = nil
    ) -> [LedgerWallet] {
        return MistiaWalletPickerAccessLogic.availableWallets(
            from: preparedWallets.snapshots,
            context: MistiaWalletPickerAccessContext(
                currentSelfUserID: currentSelfUserID,
                targetOwnerUserID: targetOwnerUserID,
                usableWalletIDs: preparedWallets.usableWalletIDs,
                preferredWalletIDs: preferredWalletIDs,
                excludesCreditCards: excludesCreditCards,
                excludedWalletID: excludedWalletID
            )
        )
        .compactMap { preparedWallets.walletByID[$0.id] }
    }

    func title(
        for wallet: LedgerWallet,
        labelMode: MistiaWalletPickerLabelMode = .contextual
    ) -> String {
        guard let snapshot = walletSnapshot(for: wallet) else {
            return wallet.name
        }
        return MistiaWalletPickerAccessLogic.title(
            for: snapshot,
            currentSelfUserID: currentSelfUserID,
            memberDisplayNames: memberDisplayNames,
            labelMode: labelMode
        )
    }

    func walletOwnerUserID(for wallet: LedgerWallet) -> UUID? {
        walletOwnerMap[wallet.id]
            ?? walletUseGrantOwnerUserID(for: wallet.id)
            ?? currentSelfUserID
    }

    func walletOwnerUserID(for walletID: UUID?) -> UUID? {
        guard let walletID else { return nil }
        return walletOwnerMap[walletID]
            ?? walletUseGrantOwnerUserID(for: walletID)
            ?? currentSelfUserID
    }

    private var memberDisplayNames: [UUID: String] {
        var names = Dictionary(
            uniqueKeysWithValues: familyContextStore.members.map { ($0.userID, $0.displayName) }
        )
        if let currentSelfUserID,
           names[currentSelfUserID] == nil,
           let displayName = sessionStore.summary?.displayName.nonEmpty {
            names[currentSelfUserID] = displayName
        }
        return names
    }

    private func walletSnapshots(from wallets: [LedgerWallet]) -> [MistiaWalletPickerWalletSnapshot] {
        wallets.compactMap(walletSnapshot)
    }

    private func walletSnapshot(for wallet: LedgerWallet) -> MistiaWalletPickerWalletSnapshot? {
        guard let ownerUserID = walletOwnerUserID(for: wallet) else {
            return nil
        }
        return MistiaWalletPickerWalletSnapshot(
            id: wallet.id,
            name: wallet.name,
            ownerUserID: ownerUserID,
            kind: wallet.kind,
            sortOrder: wallet.sortOrder,
            createdAt: wallet.createdAt,
            isArchived: wallet.isArchived,
            deletedAt: wallet.deletedAt
        )
    }

    private func walletUseGrantOwnerUserID(for walletID: UUID) -> UUID? {
        guard let currentSelfUserID else { return nil }
        return familyContextStore.permissionGrants.first {
            $0.revokedAt == nil
                && $0.granteeUserID == currentSelfUserID
                && $0.resourceType == .wallet
                && $0.permissionScope == .use
                && $0.resourceID == walletID
        }?.ownerUserID
    }
}
