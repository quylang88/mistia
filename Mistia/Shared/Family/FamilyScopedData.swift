import SwiftUI

enum FamilyScopedData {
    static func visible<Record: MistiaOwnedRecord>(
        _ records: [Record],
        entity: MistiaSyncEntity,
        scopes: [OwnedRecordScope],
        familyContextStore: FamilyContextStore,
        sessionStore: SessionStore
    ) -> [Record] {
        let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: entity)
        return MistiaRecordOwnershipStore.visibleRecords(
            records,
            entity: entity,
            ownerMap: ownerMap,
            subjectUserID: familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID,
            signedInUserID: sessionStore.activeLocalProfileUserID
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
        guard let subjectUserID = familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID else {
            return transactions
        }

        let auditMap = TransactionAuditStore.auditMap(from: audits)
        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .wallet)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .transaction)

        return transactions.filter { transaction in
            let sourceOwnerUserID = ownerUserID(forWalletID: transaction.sourceWallet?.id, ownerMap: walletOwnerMap)
            let destinationOwnerUserID = ownerUserID(forWalletID: transaction.destinationWallet?.id, ownerMap: walletOwnerMap)
            let canonicalOwnerUserID = transactionOwnerMap[transaction.id] ?? sourceOwnerUserID
            let createdByUserID = auditMap[transaction.id]?.createdByUserID ?? canonicalOwnerUserID

            return canonicalOwnerUserID == subjectUserID
                || createdByUserID == subjectUserID
                || sourceOwnerUserID == subjectUserID
                || destinationOwnerUserID == subjectUserID
        }
    }

    static func visibleTransactionsForFinancial(
        _ transactions: [LedgerTransaction],
        scopes: [OwnedRecordScope],
        familyContextStore: FamilyContextStore,
        sessionStore: SessionStore
    ) -> [LedgerTransaction] {
        guard let subjectUserID = familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID else {
            return transactions
        }

        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .wallet)

        return transactions.filter { transaction in
            ownerUserID(forWalletID: transaction.sourceWallet?.id, ownerMap: walletOwnerMap) == subjectUserID
                || ownerUserID(forWalletID: transaction.destinationWallet?.id, ownerMap: walletOwnerMap) == subjectUserID
        }
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
                        Text(mistiaLocalized(vi: "Đang xem", en: "Viewing", ja: "表示中"))
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
