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

    static func usesAggregateFamilyBudgetSpending(
        isFamilyBudgetSpendingAvailable: Bool,
        familyContextStore _: FamilyContextStore
    ) -> Bool {
        isFamilyBudgetSpendingAvailable
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

    static func visibleTransactionsForCurrentFamilyFinancial(
        _ transactions: [LedgerTransaction],
        scopeSnapshot: ScopeSnapshot,
        familyMemberUserIDs: Set<UUID>,
        signedInUserID: UUID?
    ) -> [LedgerTransaction] {
        guard !familyMemberUserIDs.isEmpty else { return [] }

        let walletOwnerMap = scopeSnapshot.ownerMap(for: .wallet)
        let transactionOwnerMap = scopeSnapshot.ownerMap(for: .transaction)
        return transactions.filter { transaction in
            guard transaction.deletedAt == nil, !transaction.isArchived else {
                return false
            }
            let ownerUserID = transactionOwnerUserID(
                for: transaction,
                transactionOwnerMap: transactionOwnerMap,
                walletOwnerMap: walletOwnerMap
            ) ?? signedInUserID
            guard let ownerUserID else { return false }
            return familyMemberUserIDs.contains(ownerUserID)
        }
    }

    static func familyBudgetTransactionSnapshots(
        from transactions: [LedgerTransaction],
        scopeSnapshot: ScopeSnapshot,
        familyMemberUserIDs: Set<UUID>,
        signedInUserID: UUID?
    ) -> [FamilyAggregateTransactionSnapshot] {
        let walletOwnerMap = scopeSnapshot.ownerMap(for: .wallet)
        let transactionOwnerMap = scopeSnapshot.ownerMap(for: .transaction)
        return visibleTransactionsForCurrentFamilyFinancial(
            transactions,
            scopeSnapshot: scopeSnapshot,
            familyMemberUserIDs: familyMemberUserIDs,
            signedInUserID: signedInUserID
        )
        .map { transaction in
            let record = transaction.planningRecordSnapshot
            return FamilyAggregateTransactionSnapshot(
                ownerUserID: transactionOwnerUserID(
                    for: transaction,
                    transactionOwnerMap: transactionOwnerMap,
                    walletOwnerMap: walletOwnerMap
                ) ?? signedInUserID ?? UUID(),
                categoryName: transaction.category?.localizedDisplayName,
                categoryParentName: transaction.category?.parentCategory?.localizedDisplayName,
                occurredAt: transaction.occurredAt,
                kind: familyAggregateKind(for: record),
                amountMinor: abs(transaction.amountMinor),
                currencyCode: record.sourceCurrencyCode ?? transaction.sourceWallet?.currencyCode ?? "JPY",
                isCreditCardPayment: TransactionLogic.isCreditCardPayment(record),
                isAdjustment: TransactionLogic.isAdjustment(record),
                isInstallmentPayment: TransactionLogic.isInstallmentPayment(record)
            )
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

    private static func familyAggregateKind(
        for record: TransactionRecordSnapshot
    ) -> FamilyAggregateTransactionSnapshot.Kind {
        if TransactionLogic.isPaidForExpenseDebt(record) {
            return .expense
        }

        switch record.primaryKind {
        case .expense:
            return .expense
        case .income:
            return .income
        case .transfer:
            return .transfer
        }
    }

}

struct FamilyMemberViewingExitPrompt: Identifiable, Equatable {
    let id = UUID()
    let presentation: FamilyMemberViewingToolbarPresentation

    init(presentation: FamilyMemberViewingToolbarPresentation) {
        self.presentation = presentation
    }
}

extension FamilyContextStore {
    var memberViewingToolbarPresentation: FamilyMemberViewingToolbarPresentation? {
        guard isViewingOtherMemberContext, let viewedMember else { return nil }
        return FamilyMemberViewingToolbarLogic.presentation(
            displayName: String(describing: viewedMember.displayName)
        )
    }
}

extension View {
    func familyMemberViewingExitAlert(
        prompt: Binding<FamilyMemberViewingExitPrompt?>,
        familyContextStore: FamilyContextStore
    ) -> some View {
        modifier(
            FamilyMemberViewingExitAlertModifier(
                prompt: prompt,
                familyContextStore: familyContextStore
            )
        )
    }
}

private struct FamilyMemberViewingExitAlertModifier: ViewModifier {
    @Binding var prompt: FamilyMemberViewingExitPrompt?
    let familyContextStore: FamilyContextStore

    func body(content: Content) -> some View {
        content.alert(
            prompt?.presentation.exitTitle ?? "",
            isPresented: Binding(
                get: { prompt != nil },
                set: { isPresented in
                    if !isPresented {
                        prompt = nil
                    }
                }
            ),
            presenting: prompt
        ) { prompt in
            Button(prompt.presentation.confirmExitTitle) {
                withAnimation(.snappy) {
                    familyContextStore.returnToSelf()
                }
                self.prompt = nil
            }
            Button(prompt.presentation.cancelTitle, role: .cancel) {
                self.prompt = nil
            }
        } message: { prompt in
            Text(prompt.presentation.exitMessage)
        }
    }
}
