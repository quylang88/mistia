import Foundation
import SwiftUI
import SwiftData

struct ManagementSyncConflictSection: Identifiable {
    let entity: MistiaSyncEntity
    let conflicts: [SyncConflict]

    var id: String { entity.rawValue }

    var title: String { entity.displayTitle }

    var systemImage: String {
        entity.managementConflictSystemImageName
    }
}

extension MistiaSyncEntity {
    var managementConflictSystemImageName: String {
        switch self {
        case .wallet:
            return "wallet.pass.fill"
        case .creditCardProfile:
            return "creditcard.fill"
        case .category:
            return "square.grid.2x2.fill"
        case .settlementGroup:
            return "hourglass.circle.fill"
        case .settlementParticipant:
            return "person.2.fill"
        case .transaction:
            return "list.bullet.rectangle.portrait.fill"
        case .budgetPlan:
            return "chart.pie.fill"
        case .savingsGoal:
            return "target"
        case .recurringBillPlan:
            return "calendar.badge.clock"
        case .installmentPlan:
            return "calendar.badge.exclamationmark"
        case .dueOccurrenceRecord:
            return "checklist"
        case .investmentChannel:
            return "square.stack.3d.up.fill"
        case .investmentAsset:
            return "chart.line.uptrend.xyaxis"
        case .investmentTrade:
            return "arrow.left.arrow.right.circle.fill"
        case .investmentPosting:
            return "list.bullet.rectangle.fill"
        }
    }
}

// MARK: - Conflict List Row

struct ManagementConflictListRow: View {
    let conflict: SyncConflict
    let accent: Color

    private var recordTitle: String {
        let localTitle = conflict.localRecordSummary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localTitle.isEmpty, localTitle != conflict.entity.displayTitle {
            return localTitle
        }

        let remoteTitle = conflict.remoteRecordSummary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remoteTitle.isEmpty {
            return remoteTitle
        }

        return conflict.entity.displayTitle
    }

    private var newerSide: String {
        conflict.isRemoteNewer
            ? L10n.management.managementauth.syncConflictCloud
            : L10n.management.managementauth.syncConflictThisDevice
    }

    private var newerIcon: String {
        conflict.isRemoteNewer ? "icloud.fill" : "iphone"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: conflict.entity.managementConflictSystemImageName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 32, height: 32)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(recordTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Label(newerSide, systemImage: newerIcon)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MistiaAccent.mint.color)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(L10n.management.managementauth.newer)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MistiaAccent.mint.color)
                }
            }

            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Conflict Detail View

struct ManagementConflictDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    let conflict: SyncConflict
    let referenceResolver: ManagementConflictReferenceResolver
    let accent: Color

    @State private var didResolve = false

    private var differences: [MistiaSyncConflictDifference] {
        conflict.conflictDifferences
    }

    private var friendlyDifferences: [MistiaSyncConflictDifference] {
        differences.map { referenceResolver.resolving($0) }
    }

    private var visibleDifferences: [MistiaSyncConflictDifference] {
        MistiaSyncConflictPresentation.visibleDifferences(from: friendlyDifferences)
    }

    private var recordTitle: String {
        let localTitle = conflict.localRecordSummary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localTitle.isEmpty, localTitle != conflict.entity.displayTitle {
            return localTitle
        }

        let remoteTitle = conflict.remoteRecordSummary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remoteTitle.isEmpty {
            return remoteTitle
        }

        return conflict.entity.displayTitle
    }

    private var localTimeString: String {
        guard let date = conflict.localUpdatedAt else { return "" }
        return MistiaDateFormatting.dateTimeString(for: date)
    }

    private var remoteTimeString: String {
        guard let date = conflict.remoteUpdatedAt else { return "" }
        return MistiaDateFormatting.dateTimeString(for: date)
    }

    private var isDisabled: Bool {
        !sessionStore.canPerformRemoteActions || didResolve
    }

    var body: some View {
        List {
            // Header section
            Section {
                HStack(spacing: 12) {
                    Image(systemName: conflict.entity.managementConflictSystemImageName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 40, height: 40)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recordTitle)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))

                        Text(conflict.entity.displayTitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
            }

            // Differences section
            if visibleDifferences.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(L10n.management.managementauth.conflictInUpdateTiming)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(visibleDifferences) { difference in
                    Section(header: Text(difference.fieldTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .textCase(nil)
                    ) {
                        // Local value
                        HStack(spacing: 10) {
                            Label {
                                Text(L10n.management.managementauth.syncConflictThisDevice)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            } icon: {
                                Image(systemName: "iphone")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(accent)

                            if !conflict.isRemoteNewer {
                                Text(L10n.management.managementauth.newer)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(MistiaAccent.mint.color, in: Capsule())
                            }

                            Spacer()

                            Text(difference.localValue)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.trailing)
                        }

                        // Remote value
                        HStack(spacing: 10) {
                            Label {
                                Text(L10n.management.managementauth.syncConflictCloud)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            } icon: {
                                Image(systemName: "icloud.fill")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(MistiaAccent.sky.color)

                            if conflict.isRemoteNewer {
                                Text(L10n.management.managementauth.newer)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(MistiaAccent.mint.color, in: Capsule())
                            }

                            Spacer()

                            Text(difference.remoteValue)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            // Timestamp section
            if !localTimeString.isEmpty || !remoteTimeString.isEmpty {
                Section(header: Text(L10n.management.managementauth.conflictInUpdateTiming)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .textCase(nil)
                ) {
                    if !localTimeString.isEmpty {
                        HStack {
                            Label(L10n.management.managementauth.syncConflictThisDevice, systemImage: "iphone")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(localTimeString)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                    }

                    if !remoteTimeString.isEmpty {
                        HStack {
                            Label(L10n.management.managementauth.syncConflictCloud, systemImage: "icloud")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(remoteTimeString)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            // Resolve actions section
            Section {
                Button {
                    resolve(.useLocal)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .font(.system(size: 14, weight: .semibold))

                        Text(L10n.management.managementauth.syncConflictKeepThisDevice)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))

                        Spacer()

                        if !conflict.isRemoteNewer {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(MistiaAccent.mint.color)
                        }
                    }
                    .foregroundStyle(conflict.isRemoteNewer ? .primary : accent)
                }
                .disabled(isDisabled)

                Button {
                    resolve(.useRemote)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 14, weight: .semibold))

                        Text(L10n.management.managementauth.syncConflictKeepCloud)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))

                        Spacer()

                        if conflict.isRemoteNewer {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(MistiaAccent.mint.color)
                        }
                    }
                    .foregroundStyle(conflict.isRemoteNewer ? accent : .primary)
                }
                .disabled(isDisabled)
            } footer: {
                Text(L10n.management.managementauth.syncConflictReviewSubtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(conflict.entity.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resolve(_ resolution: MistiaSyncConflictResolution) {
        didResolve = true
        Task {
            await sessionStore.resolveSyncConflict(
                id: conflict.id,
                resolution: resolution
            )
            dismiss()
        }
    }
}

// MARK: - Reference Resolver

struct ManagementConflictReferenceResolver {
    let wallets: [LedgerWallet]
    let creditCardProfiles: [CreditCardProfile]
    let categories: [TransactionCategory]
    let transactions: [LedgerTransaction]
    let budgetPlans: [BudgetPlan]
    let savingsGoals: [SavingsGoal]
    let recurringBillPlans: [RecurringBillPlan]
    let installmentPlans: [InstallmentPlan]
    let dueOccurrences: [DueOccurrenceRecord]

    func resolving(_ difference: MistiaSyncConflictDifference) -> MistiaSyncConflictDifference {
        MistiaSyncConflictDifference(
            id: difference.id,
            fieldTitle: difference.fieldTitle,
            localValue: resolvedValue(for: difference.id, rawValue: difference.localRawValue, fallback: difference.localValue),
            remoteValue: resolvedValue(for: difference.id, rawValue: difference.remoteRawValue, fallback: difference.remoteValue),
            localRawValue: difference.localRawValue,
            remoteRawValue: difference.remoteRawValue
        )
    }

    private func resolvedValue(for fieldID: String, rawValue: String?, fallback: String) -> String {
        guard let rawValue, let uuid = UUID(uuidString: rawValue) else {
            return fallback
        }

        switch fieldID {
        case "wallet",
             "walletID",
             "walletId",
             "wallet_id",
             "sourceWallet",
             "sourceWalletID",
             "sourceWalletId",
             "source_wallet_id",
             "destinationWallet",
             "destinationWalletID",
             "destinationWalletId",
             "destination_wallet_id",
             "paymentWallet",
             "paymentWalletID",
             "paymentWalletId",
             "payment_wallet_id",
             "linkedWallet",
             "linkedWalletID",
             "linkedWalletId",
             "linked_wallet_id":
            return walletName(for: uuid) ?? unavailableName
        case "category",
             "categoryID",
             "categoryId",
             "category_id",
             "parent",
             "parentCategoryID",
             "parentCategoryId",
             "parent_category_id":
            return categoryName(for: uuid) ?? unavailableName
        case "transaction",
             "transactionID",
             "transactionId",
             "transaction_id",
             "linkedTransactionID",
             "linkedTransactionId",
             "linked_transaction_id":
            return transactionName(for: uuid) ?? unavailableName
        case "source", "sourceID", "sourceId", "source_id":
            return sourceName(for: uuid) ?? unavailableName
        default:
            return genericName(for: uuid) ?? unavailableName
        }
    }

    private func walletName(for id: UUID) -> String? {
        wallets.first { $0.id == id }.map { wallet in
            compactConflictName(wallet.name, wallet.currencyCode)
        }
    }

    private func categoryName(for id: UUID) -> String? {
        categories.first { $0.id == id }.map { category in
            if let parent = category.parentCategory {
                return "\(parent.localizedDisplayName) / \(category.localizedDisplayName)"
            }
            return category.localizedDisplayName
        }
    }

    private func transactionName(for id: UUID) -> String? {
        transactions.first { $0.id == id }.map { transaction in
            let title = transaction.localizedTransactionTitle.isEmpty
                ? L10n.management.managementauth.unnamedTransaction
                : transaction.localizedTransactionTitle
            let currencyCode = transaction.sourceWallet?.currencyCode ?? transaction.destinationWallet?.currencyCode ?? "JPY"
            return compactConflictName(title, transaction.amountMinor.formattedCurrency(code: currencyCode))
        }
    }

    private func creditCardName(for id: UUID) -> String? {
        creditCardProfiles.first { $0.id == id }.map { profile in
            profile.issuerName.isEmpty ? profile.last4 : compactConflictName(profile.issuerName, profile.last4)
        }
    }

    private func budgetName(for id: UUID) -> String? {
        budgetPlans.first { $0.id == id }.map { plan in
            compactConflictName(
                plan.category?.localizedDisplayName ?? L10n.management.managementauth.budget,
                plan.limitMinor.formattedCurrency(code: plan.currencyCode)
            )
        }
    }

    private func goalName(for id: UUID) -> String? {
        savingsGoals.first { $0.id == id }?.name
    }

    private func recurringBillName(for id: UUID) -> String? {
        recurringBillPlans.first { $0.id == id }?.name
    }

    private func installmentName(for id: UUID) -> String? {
        installmentPlans.first { $0.id == id }?.name
    }

    private func dueOccurrenceName(for id: UUID) -> String? {
        dueOccurrences.first { $0.id == id }.map { due in
            compactConflictName(
                L10n.management.managementauth.dueOccurrence,
                due.selectedMonthKey
            )
        }
    }

    private func sourceName(for id: UUID) -> String? {
        recurringBillName(for: id)
            ?? installmentName(for: id)
            ?? budgetName(for: id)
            ?? goalName(for: id)
            ?? creditCardName(for: id)
            ?? transactionName(for: id)
            ?? walletName(for: id)
            ?? categoryName(for: id)
    }

    private func genericName(for id: UUID) -> String? {
        walletName(for: id)
            ?? categoryName(for: id)
            ?? transactionName(for: id)
            ?? creditCardName(for: id)
            ?? budgetName(for: id)
            ?? goalName(for: id)
            ?? recurringBillName(for: id)
            ?? installmentName(for: id)
            ?? dueOccurrenceName(for: id)
    }

    private var unavailableName: String {
        L10n.management.managementauth.nameUnavailable
    }

    private func compactConflictName(_ values: String?...) -> String {
        values
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " • ")
    }
}

// MARK: - Data Conflicts View

struct ManagementDataConflictsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Query private var storedConflicts: [SyncConflict]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<CreditCardProfile> { $0.deletedAt == nil })
    private var storedCreditCardProfiles: [CreditCardProfile]
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil })
    private var storedTransactions: [LedgerTransaction]
    @Query(filter: #Predicate<BudgetPlan> { $0.deletedAt == nil })
    private var storedBudgetPlans: [BudgetPlan]
    @Query(filter: #Predicate<SavingsGoal> { $0.deletedAt == nil })
    private var storedSavingsGoals: [SavingsGoal]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil })
    private var storedRecurringBillPlans: [RecurringBillPlan]
    @Query(filter: #Predicate<InstallmentPlan> { $0.deletedAt == nil })
    private var storedInstallmentPlans: [InstallmentPlan]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedDueOccurrences: [DueOccurrenceRecord]

    let accent: Color

    private var activeConflicts: [SyncConflict] {
        storedConflicts
    }

    private var referenceResolver: ManagementConflictReferenceResolver {
        ManagementConflictReferenceResolver(
            wallets: storedWallets,
            creditCardProfiles: storedCreditCardProfiles,
            categories: storedCategories,
            transactions: storedTransactions,
            budgetPlans: storedBudgetPlans,
            savingsGoals: storedSavingsGoals,
            recurringBillPlans: storedRecurringBillPlans,
            installmentPlans: storedInstallmentPlans,
            dueOccurrences: storedDueOccurrences
        )
    }

    private var conflictSections: [ManagementSyncConflictSection] {
        MistiaSyncEntity.allCases.compactMap { entity in
            let rows = activeConflicts.filter { $0.entity == entity }
            guard !rows.isEmpty else { return nil }
            return ManagementSyncConflictSection(entity: entity, conflicts: rows)
        }
    }

    var body: some View {
        let resolver = referenceResolver
        List {
            // Network unavailable banner
            if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.management.managementauth.resolvingConflictsNeedsTheNetwork)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(remoteUnavailableReason)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(MistiaAccent.sky.color)
                    }
                }
            }

            if activeConflicts.isEmpty {
                // Empty state
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(accent)

                        Text(L10n.management.managementauth.noConflictsYet)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))

                        Text(L10n.management.managementauth.whenSyncConflictsOrReviewNeededData)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            } else {
                // Batch action
                Section {
                    Button {
                        applyNewestToAll()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))

                            Text(L10n.management.managementauth.applyNewestToAll)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))

                            Spacer()

                            Text(verbatim: "\(activeConflicts.count)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(accent, in: Capsule())
                        }
                        .foregroundStyle(accent)
                    }
                    .disabled(!sessionStore.canPerformRemoteActions)
                } footer: {
                    Text(L10n.management.managementauth.syncConflictReviewSubtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                }

                // Conflict sections grouped by entity
                ForEach(conflictSections) { section in
                    Section(header:
                        HStack(spacing: 8) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(accent)

                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .textCase(nil)

                            Spacer()

                            Text(verbatim: "\(section.conflicts.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MistiaAccent.purple.color, in: Capsule())
                        }
                    ) {
                        ForEach(section.conflicts) { conflict in
                            NavigationLink {
                                ManagementConflictDetailView(
                                    conflict: conflict,
                                    referenceResolver: resolver,
                                    accent: accent
                                )
                            } label: {
                                ManagementConflictListRow(
                                    conflict: conflict,
                                    accent: accent
                                )
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.management.managementauth.manageSyncedData)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func applyNewestToAll() {
        Task {
            for conflict in activeConflicts {
                let resolution: MistiaSyncConflictResolution = conflict.isRemoteNewer ? .useRemote : .useLocal
                await sessionStore.resolveSyncConflict(id: conflict.id, resolution: resolution)
            }
        }
    }
}
