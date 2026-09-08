import Foundation
import SwiftUI
import SwiftData

struct ManagementSyncConflictSection: Identifiable {
    let entity: MistiaSyncEntity
    let conflicts: [SyncConflict]

    var id: String { entity.rawValue }
    var title: String { entity.displayTitle }
    var systemImage: String { entity.managementConflictSystemImageName }
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

// MARK: - High-Performance In-Memory Conflict Reference Resolver

struct ManagementConflictReferenceResolver {
    let walletNames: [UUID: String]
    let categoryNames: [UUID: String]
    let transactionNames: [UUID: String]
    let cardNames: [UUID: String]
    let otherEntityNames: [UUID: String]

    init(
        wallets: [LedgerWallet],
        creditCardProfiles: [CreditCardProfile],
        categories: [TransactionCategory],
        transactions: [LedgerTransaction],
        budgetPlans: [BudgetPlan],
        savingsGoals: [SavingsGoal],
        recurringBillPlans: [RecurringBillPlan],
        installmentPlans: [InstallmentPlan],
        dueOccurrences: [DueOccurrenceRecord]
    ) {
        var w = [UUID: String]()
        for wallet in wallets {
            let name = wallet.name.trimmingCharacters(in: .whitespacesAndNewlines)
            w[wallet.id] = name.isEmpty ? wallet.currencyCode : "\(name) • \(wallet.currencyCode)"
        }
        self.walletNames = w

        var c = [UUID: String]()
        for cat in categories {
            if let parent = cat.parentCategory {
                c[cat.id] = "\(parent.localizedDisplayName) / \(cat.localizedDisplayName)"
            } else {
                c[cat.id] = cat.localizedDisplayName
            }
        }
        self.categoryNames = c

        var t = [UUID: String]()
        for tx in transactions {
            let title = tx.localizedTransactionTitle.isEmpty
                ? L10n.management.managementauth.unnamedTransaction
                : tx.localizedTransactionTitle
            t[tx.id] = title
        }
        self.transactionNames = t

        var cc = [UUID: String]()
        for card in creditCardProfiles {
            cc[card.id] = card.issuerName.isEmpty ? card.last4 : "\(card.issuerName) • \(card.last4)"
        }
        self.cardNames = cc

        var others = [UUID: String]()
        for plan in budgetPlans {
            let name = plan.category?.localizedDisplayName ?? L10n.management.managementauth.budget
            others[plan.id] = "\(name) • \(plan.limitMinor.formattedCurrency(code: plan.currencyCode))"
        }
        for goal in savingsGoals { others[goal.id] = goal.name }
        for bill in recurringBillPlans { others[bill.id] = bill.name }
        for inst in installmentPlans { others[inst.id] = inst.name }
        for due in dueOccurrences {
            others[due.id] = "\(L10n.management.managementauth.dueOccurrence) • \(due.selectedMonthKey)"
        }
        self.otherEntityNames = others
    }

    func resolving(_ difference: MistiaSyncConflictDifference) -> MistiaSyncConflictDifference {
        guard let rawLocal = difference.localRawValue, let rawRemote = difference.remoteRawValue else {
            return difference
        }

        let resolvedLocal = resolve(fieldID: difference.id, rawValue: rawLocal) ?? difference.localValue
        let resolvedRemote = resolve(fieldID: difference.id, rawValue: rawRemote) ?? difference.remoteValue

        return MistiaSyncConflictDifference(
            id: difference.id,
            fieldTitle: difference.fieldTitle,
            localValue: resolvedLocal,
            remoteValue: resolvedRemote,
            localRawValue: difference.localRawValue,
            remoteRawValue: difference.remoteRawValue
        )
    }

    func semanticDifferences(for conflict: SyncConflict) -> [MistiaSyncConflictDifference] {
        let diffs = conflict.conflictDifferences
        let friendly = diffs.map { resolving($0) }
        let userFacing = friendly.filter { !MistiaSyncConflictPresentation.isInternalField($0.id) }
        return userFacing.filter { !MistiaSyncConflictPresentation.isMetadataField($0.id) }
    }

    private func resolve(fieldID: String, rawValue: String) -> String? {
        guard let uuid = UUID(uuidString: rawValue) else { return nil }
        let lower = fieldID.lowercased()

        if lower.contains("wallet") {
            return walletNames[uuid]
        }
        if lower.contains("category") || lower == "parent" {
            return categoryNames[uuid]
        }
        if lower.contains("transaction") {
            return transactionNames[uuid]
        }
        if lower.contains("card") || lower.contains("issuer") {
            return cardNames[uuid]
        }
        return otherEntityNames[uuid]
    }
}

extension SyncConflict {
    var conflictDisplayTitle: String {
        let localTitle = localRecordSummary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localTitle.isEmpty, localTitle != entity.displayTitle {
            return localTitle
        }
        let remoteTitle = remoteRecordSummary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remoteTitle.isEmpty {
            return remoteTitle
        }
        return entity.displayTitle
    }
}

// MARK: - Main Conflicts View (Scaffold & Mistia Design System)

struct ManagementDataConflictsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
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

    private var cardTint: Color {
        colorScheme == .dark
            ? Color(UIColor.secondarySystemGroupedBackground).opacity(0.96)
            : .white.opacity(0.85)
    }

    /// Only records with genuine semantic differences qualify as user-facing conflicts.
    private var activeConflicts: [SyncConflict] {
        storedConflicts.filter(\.hasSemanticDifferences)
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

        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.management.managementauth.manageSyncedData,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 16,
            contentBottomPadding: 120
        ) {
            // Network warning banner
            if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                networkWarningCard(reason: remoteUnavailableReason)
            }

            // Hero overview summary card
            heroOverviewCard

            // Entity sections
            ForEach(conflictSections) { section in
                conflictSectionCard(section: section, resolver: resolver)
            }
        }
        .task {
            modelContext.purgeNonSemanticConflicts(from: storedConflicts)
        }
        .onChange(of: activeConflicts.isEmpty) { _, isEmpty in
            if isEmpty {
                dismiss()
            }
        }
    }

    // MARK: - Subviews

    private func networkWarningCard(reason: String) -> some View {
        MistiaGlassCard(cornerRadius: 18, tint: MistiaAccent.sky.color.opacity(0.12)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MistiaAccent.sky.color)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.management.managementauth.resolvingConflictsNeedsTheNetwork)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(reason)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var heroOverviewCard: some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(accent.opacity(0.12))

                        Image(systemName: "arrow.triangle.2.circlepath.icloud")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.management.managementauth.syncConflictReviewTitle)
                            .font(.system(size: 16.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(L10n.management.managementauth.syncConflictReviewSubtitle)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Text(verbatim: "\(activeConflicts.count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accent, in: Capsule())
                }

                // Batch resolve button
                Button {
                    applyNewestToAll()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))

                        Text(L10n.management.managementauth.applyNewestToAll)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        accent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!sessionStore.canPerformRemoteActions)
                .opacity(sessionStore.canPerformRemoteActions ? 1.0 : 0.55)
            }
        }
    }

    private func conflictSectionCard(
        section: ManagementSyncConflictSection,
        resolver: ManagementConflictReferenceResolver
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)

                Text(section.title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(verbatim: "\(section.conflicts.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(UIColor.tertiarySystemFill), in: Capsule())
            }
            .padding(.horizontal, 4)

            // Section Card Items with Native NavigationLink
            MistiaGlassCard(cornerRadius: 20, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(section.conflicts.enumerated()), id: \.element.id) { index, conflict in
                        NavigationLink {
                            ManagementConflictDetailView(
                                conflict: conflict,
                                referenceResolver: resolver,
                                accent: accent
                            )
                        } label: {
                            ManagementConflictListRowView(
                                conflict: conflict,
                                resolver: resolver,
                                accent: accent
                            )
                        }
                        .buttonStyle(.plain)

                        if index < section.conflicts.count - 1 {
                            Divider()
                                .padding(.leading, 62)
                        }
                    }
                }
            }
        }
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

// MARK: - Conflict List Row Component

private struct ManagementConflictListRowView: View {
    let conflict: SyncConflict
    let resolver: ManagementConflictReferenceResolver
    let accent: Color

    private var recordTitle: String {
        conflict.conflictDisplayTitle
    }

    private var differenceSummaryText: String {
        let fieldNames = resolver.semanticDifferences(for: conflict).map(\.fieldTitle)
        return L10n.management.managementauth.syncConflictDifferentPrefix(fieldNames.joined(separator: ", "))
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.opacity(0.12))

                Image(systemName: conflict.entity.managementConflictSystemImageName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 38, height: 38)

            // Titles
            VStack(alignment: .leading, spacing: 3) {
                Text(recordTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(differenceSummaryText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)

                // Recommendation Badge
                HStack(spacing: 4) {
                    Image(systemName: conflict.isRemoteNewer ? "icloud.fill" : "iphone")
                        .font(.system(size: 10, weight: .bold))

                    Text(conflict.isRemoteNewer
                         ? "\(L10n.management.managementauth.syncConflictCloud) \(L10n.management.managementauth.newer.lowercased())"
                         : "\(L10n.management.managementauth.syncConflictThisDevice) \(L10n.management.managementauth.newer.lowercased())")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(conflict.isRemoteNewer ? MistiaAccent.sky.color : MistiaAccent.mint.color)
                .padding(.top, 1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Conflict Detail View (Apple Minimalist Design & Instant Render)

struct ManagementConflictDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    let conflict: SyncConflict
    let accent: Color

    let recordTitle: String
    let localTimeString: String
    let remoteTimeString: String
    let semanticDifferences: [MistiaSyncConflictDifference]

    @State private var didResolve = false

    init(
        conflict: SyncConflict,
        referenceResolver: ManagementConflictReferenceResolver,
        accent: Color
    ) {
        self.conflict = conflict
        self.accent = accent
        self.recordTitle = conflict.conflictDisplayTitle

        if let lDate = conflict.localUpdatedAt {
            self.localTimeString = MistiaDateFormatting.dateTimeString(for: lDate)
        } else {
            self.localTimeString = ""
        }

        if let rDate = conflict.remoteUpdatedAt {
            self.remoteTimeString = MistiaDateFormatting.dateTimeString(for: rDate)
        } else {
            self.remoteTimeString = ""
        }

        self.semanticDifferences = referenceResolver.semanticDifferences(for: conflict)
    }

    private var cardTint: Color {
        colorScheme == .dark
            ? Color(UIColor.secondarySystemGroupedBackground).opacity(0.96)
            : .white.opacity(0.85)
    }

    private var isDisabled: Bool {
        !sessionStore.canPerformRemoteActions || didResolve
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: conflict.entity.displayTitle,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 16,
            contentBottomPadding: 120
        ) {
            // 1. Record Header Card
            recordHeroCard

            // 2. Differences Comparison Section
            semanticDifferencesSection

            // 3. Timestamps Section
            timestampsCard

            // 4. Resolve Action Buttons
            resolveActionsCard
        }
    }

    // MARK: - Subcomponents

    private var recordHeroCard: some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.12))

                        Image(systemName: conflict.entity.managementConflictSystemImageName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(recordTitle)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(conflict.entity.displayTitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                // Recommendation banner
                HStack(spacing: 8) {
                    Image(systemName: conflict.isRemoteNewer ? "icloud.fill" : "iphone")
                        .font(.system(size: 12, weight: .bold))

                    Text(conflict.isRemoteNewer
                         ? L10n.management.managementauth.syncConflictCloudNewerBanner
                         : L10n.management.managementauth.syncConflictDeviceNewerBanner)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(conflict.isRemoteNewer ? MistiaAccent.sky.color : MistiaAccent.mint.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    (conflict.isRemoteNewer ? MistiaAccent.sky.color : MistiaAccent.mint.color).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
    }

    private var semanticDifferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.management.managementauth.syncConflictDifferences.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(L10n.management.managementauth.syncConflictFieldCount(semanticDifferences.count))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(semanticDifferences) { difference in
                    differenceFieldCard(difference: difference)
                }
            }
        }
    }

    private func differenceFieldCard(difference: MistiaSyncConflictDifference) -> some View {
        MistiaGlassCard(cornerRadius: 18, tint: cardTint) {
            VStack(alignment: .leading, spacing: 12) {
                // Field Header
                Text(difference.fieldTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                // Comparison Columns
                VStack(spacing: 8) {
                    // Local Value Row
                    HStack(alignment: .top, spacing: 10) {
                        HStack(spacing: 5) {
                            Image(systemName: "iphone")
                                .font(.system(size: 12, weight: .bold))
                            Text(L10n.management.managementauth.syncConflictThisDevice)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(accent)
                        .frame(width: 85, alignment: .leading)

                        Text(difference.localValue)
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !conflict.isRemoteNewer {
                            Text(L10n.management.managementauth.newer)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MistiaAccent.mint.color, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Color(UIColor.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                    // Cloud Value Row
                    HStack(alignment: .top, spacing: 10) {
                        HStack(spacing: 5) {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(L10n.management.managementauth.syncConflictCloud)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(MistiaAccent.sky.color)
                        .frame(width: 85, alignment: .leading)

                        Text(difference.remoteValue)
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if conflict.isRemoteNewer {
                            Text(L10n.management.managementauth.newer)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MistiaAccent.mint.color, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Color(UIColor.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
            }
        }
    }

    private var timestampsCard: some View {
        MistiaGlassCard(cornerRadius: 20, tint: cardTint) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.management.managementauth.syncConflictUpdateTimes.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    if !localTimeString.isEmpty {
                        HStack {
                            Label(L10n.management.managementauth.syncConflictThisDevice, systemImage: "iphone")
                                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(localTimeString)
                                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                    }

                    if !localTimeString.isEmpty && !remoteTimeString.isEmpty {
                        Divider()
                    }

                    if !remoteTimeString.isEmpty {
                        HStack {
                            Label(L10n.management.managementauth.syncConflictCloud, systemImage: "icloud")
                                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(remoteTimeString)
                                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    private var resolveActionsCard: some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint) {
            VStack(spacing: 12) {
                Text(L10n.management.managementauth.syncConflictChooseVersion.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Button 1: Cloud
                Button {
                    resolve(.useRemote)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 16, weight: .bold))

                        Text(L10n.management.managementauth.syncConflictKeepCloud)
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                        Spacer()

                        if conflict.isRemoteNewer {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                Text(L10n.management.managementauth.recommended)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(MistiaAccent.mint.color, in: Capsule())
                        }
                    }
                    .foregroundStyle(conflict.isRemoteNewer ? .white : accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        conflict.isRemoteNewer
                            ? accent
                            : accent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)

                // Button 2: This Device
                Button {
                    resolve(.useLocal)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .font(.system(size: 16, weight: .bold))

                        Text(L10n.management.managementauth.syncConflictKeepThisDevice)
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                        Spacer()

                        if !conflict.isRemoteNewer {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                Text(L10n.management.managementauth.recommended)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(MistiaAccent.mint.color, in: Capsule())
                        }
                    }
                    .foregroundStyle(!conflict.isRemoteNewer ? .white : accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        !conflict.isRemoteNewer
                            ? accent
                            : accent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
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
