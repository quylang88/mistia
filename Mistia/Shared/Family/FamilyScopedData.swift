import SwiftUI

enum FamilyScopedData {
    struct ScopeSnapshot {
        let subjectUserID: UUID?
        let signedInUserID: UUID?
        private let ownersByEntity: [MistiaSyncEntity: [UUID: UUID]]

        init(
            scopes: [OwnedRecordScope],
            familyContextStore: FamilyContextStore,
            sessionStore: SessionStore
        ) {
            self.subjectUserID = familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID
            self.signedInUserID = sessionStore.activeLocalProfileUserID

            var latestOwners: [MistiaSyncEntity: [UUID: (ownerUserID: UUID, updatedAt: Date)]] = [:]
            for scope in scopes {
                let entity = scope.entity
                if let existing = latestOwners[entity]?[scope.recordID],
                   existing.updatedAt > scope.updatedAt {
                    continue
                }
                latestOwners[entity, default: [:]][scope.recordID] = (scope.ownerUserID, scope.updatedAt)
            }
            self.ownersByEntity = latestOwners.mapValues { owners in
                owners.mapValues(\.ownerUserID)
            }
        }

        func ownerMap(for entity: MistiaSyncEntity) -> [UUID: UUID] {
            ownersByEntity[entity] ?? [:]
        }
    }

    static func visible<Record: MistiaOwnedRecord>(
        _ records: [Record],
        entity: MistiaSyncEntity,
        scopes: [OwnedRecordScope],
        familyContextStore: FamilyContextStore,
        sessionStore: SessionStore
    ) -> [Record] {
        visible(
            records,
            entity: entity,
            scopeSnapshot: ScopeSnapshot(
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            )
        )
    }

    static func visible<Record: MistiaOwnedRecord>(
        _ records: [Record],
        entity: MistiaSyncEntity,
        scopeSnapshot: ScopeSnapshot
    ) -> [Record] {
        let ownerMap = scopeSnapshot.ownerMap(for: entity)

        return MistiaRecordOwnershipStore.visibleRecords(
            records,
            entity: entity,
            ownerMap: ownerMap,
            subjectUserID: scopeSnapshot.subjectUserID,
            signedInUserID: scopeSnapshot.signedInUserID
        )
    }

    static func visibleForFamilyOverview<Record: MistiaOwnedRecord>(
        _ records: [Record],
        entity: MistiaSyncEntity,
        scopes: [OwnedRecordScope],
        familyMemberUserIDs: Set<UUID>,
        familyContextStore: FamilyContextStore,
        sessionStore: SessionStore
    ) -> [Record] {
        let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: entity)

        switch familyContextStore.activeContext.scope {
        case .familyHome:
            return records.filter { record in
                let ownerUserID = ownerMap[record.id] ?? sessionStore.activeLocalProfileUserID
                guard let ownerUserID else { return false }
                return familyMemberUserIDs.contains(ownerUserID)
            }
        case .personalSelf, .member:
            return visible(
                records,
                entity: entity,
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            )
        }
    }

    static func visibleTransactionsForHistory(
        _ transactions: [LedgerTransaction],
        audits: [TransactionAuditRecord],
        scopes: [OwnedRecordScope],
        familyContextStore: FamilyContextStore,
        sessionStore: SessionStore
    ) -> [LedgerTransaction] {
        visibleTransactionsForHistory(
            transactions,
            audits: audits,
            scopeSnapshot: ScopeSnapshot(
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            )
        )
    }

    static func visibleTransactionsForHistory(
        _ transactions: [LedgerTransaction],
        audits _: [TransactionAuditRecord],
        scopeSnapshot: ScopeSnapshot
    ) -> [LedgerTransaction] {
        guard let subjectUserID = scopeSnapshot.subjectUserID else {
            return transactions
        }

        let walletOwnerMap = scopeSnapshot.ownerMap(for: .wallet)
        let transactionOwnerMap = scopeSnapshot.ownerMap(for: .transaction)
        return transactions.filter { transaction in
            guard transaction.deletedAt == nil, !transaction.isArchived else {
                return false
            }
            return transactionOwnerUserID(
                for: transaction,
                transactionOwnerMap: transactionOwnerMap,
                walletOwnerMap: walletOwnerMap
            ) == subjectUserID
        }
    }

    static func visibleTransactionsForFinancial(
        _ transactions: [LedgerTransaction],
        scopes: [OwnedRecordScope],
        familyContextStore: FamilyContextStore,
        sessionStore: SessionStore
    ) -> [LedgerTransaction] {
        visibleTransactionsForFinancial(
            transactions,
            scopeSnapshot: ScopeSnapshot(
                scopes: scopes,
                familyContextStore: familyContextStore,
                sessionStore: sessionStore
            )
        )
    }

    static func visibleTransactionsForFinancial(
        _ transactions: [LedgerTransaction],
        scopeSnapshot: ScopeSnapshot
    ) -> [LedgerTransaction] {
        guard let subjectUserID = scopeSnapshot.subjectUserID else {
            return transactions
        }

        let walletOwnerMap = scopeSnapshot.ownerMap(for: .wallet)
        let transactionOwnerMap = scopeSnapshot.ownerMap(for: .transaction)
        return transactions.filter { transaction in
            guard transaction.deletedAt == nil, !transaction.isArchived else {
                return false
            }
            return transactionOwnerUserID(
                for: transaction,
                transactionOwnerMap: transactionOwnerMap,
                walletOwnerMap: walletOwnerMap
            ) == subjectUserID
        }
    }

    private static func transactionOwnerUserID(
        for transaction: LedgerTransaction,
        transactionOwnerMap: [UUID: UUID],
        walletOwnerMap: [UUID: UUID]
    ) -> UUID? {
        transactionOwnerMap[transaction.id]
            ?? ownerUserID(forWalletID: transaction.sourceWallet?.id, ownerMap: walletOwnerMap)
            ?? ownerUserID(forWalletID: transaction.destinationWallet?.id, ownerMap: walletOwnerMap)
    }

    private static func ownerUserID(
        forWalletID walletID: UUID?,
        ownerMap: [UUID: UUID]
    ) -> UUID? {
        guard let walletID else { return nil }
        return ownerMap[walletID]
    }

}

struct FamilyContextChipBar: View {
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    var body: some View {
        if familyContextStore.isViewingOtherMemberContext, let viewedMember = familyContextStore.viewedMember {
            Button {
                withAnimation(.snappy) {
                    familyContextStore.returnToSelf()
                }
            } label: {
                HStack(spacing: 7) {
                    MistiaAvatarBadge(
                        initials: String(viewedMember.displayName.prefix(2)).uppercased(),
                        avatarURL: viewedMember.avatarURL,
                        size: 22,
                        showsStatus: false
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(accent.opacity(colorScheme == .dark ? 0.42 : 0.28), lineWidth: 1)
                    }

                    HStack(spacing: 4) {
                        Text(L10n.shared.family.familyscopeddata.viewing)
                            .foregroundStyle(.secondary)

                        Text(viewedMember.displayName)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 6)
                .padding(.trailing, 9)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(colorScheme == .dark ? 0.86 : 0.72))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.16), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(familyContextStore.contextChipTitle ?? viewedMember.displayName))
            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            .padding(.bottom, 4)
        }
    }
}
