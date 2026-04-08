import Foundation
import SwiftData

enum MistiaBootstrap {
    static func cleanupExpiredArchivedData(
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) throws {
        guard sessionStore.canManageSync else { return }

        let thresholdDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        var didDelete = false
        
        var txDescriptor = FetchDescriptor<LedgerTransaction>()
        txDescriptor.predicate = #Predicate<LedgerTransaction> { $0.isArchived == true }
        for transaction in try modelContext.fetch(txDescriptor) {
            if let archivedAt = transaction.archivedAt, archivedAt < thresholdDate {
                if transaction.deletedAt == nil {
                    transaction.markDeleted(at: .now)
                    sessionStore.recordDelete(
                        entity: .transaction,
                        recordID: transaction.id,
                        modifiedAt: transaction.updatedAt
                    )
                    didDelete = true
                } else if sessionStore.canHardPurge(entity: .transaction, recordID: transaction.id) {
                    modelContext.delete(transaction)
                    didDelete = true
                }
            }
        }
        
        var walletDescriptor = FetchDescriptor<LedgerWallet>()
        walletDescriptor.predicate = #Predicate<LedgerWallet> { $0.isArchived == true }
        for wallet in try modelContext.fetch(walletDescriptor) {
            if let archivedAt = wallet.archivedAt, archivedAt < thresholdDate {
                if wallet.deletedAt == nil {
                    wallet.markDeleted(at: .now)
                    sessionStore.recordDelete(
                        entity: .wallet,
                        recordID: wallet.id,
                        modifiedAt: wallet.updatedAt
                    )
                    didDelete = true
                } else if sessionStore.canHardPurge(entity: .wallet, recordID: wallet.id) {
                    modelContext.delete(wallet)
                    didDelete = true
                }
            }
        }
        
        var categoryDescriptor = FetchDescriptor<TransactionCategory>()
        categoryDescriptor.predicate = #Predicate<TransactionCategory> { $0.isArchived == true }
        for category in try modelContext.fetch(categoryDescriptor) {
            if let archivedAt = category.archivedAt, archivedAt < thresholdDate {
                if category.deletedAt == nil {
                    category.markDeleted(at: .now)
                    sessionStore.recordDelete(
                        entity: .category,
                        recordID: category.id,
                        modifiedAt: category.updatedAt
                    )
                    didDelete = true
                } else if sessionStore.canHardPurge(entity: .category, recordID: category.id) {
                    modelContext.delete(category)
                    didDelete = true
                }
            }
        }
        
        if didDelete {
            try modelContext.save()
        }
    }

    static func seedDefaultCategoriesIfNeeded(modelContext: ModelContext) throws {
        let existingCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            .filter { $0.deletedAt == nil }
        let existingWallets = try modelContext.fetch(FetchDescriptor<LedgerWallet>())
            .filter { $0.deletedAt == nil }
        var didMutate = false

        if normalizeLegacyDefaultIconColors(
            categories: existingCategories,
            wallets: existingWallets
        ) {
            didMutate = true
        }

        if existingCategories.isEmpty {
            for (index, seed) in ManagementPresetData.defaultCategorySeeds.enumerated() {
                let category = TransactionCategory(
                    name: seed.name,
                    kind: seed.kind,
                    iconSymbolName: seed.iconSymbolName,
                    iconColorHex: seed.iconColorHex,
                    systemKey: seed.systemKey?.rawValue,
                    isSystem: true,
                    sortOrder: index,
                    isArchived: seed.startsArchived
                )
                modelContext.insert(category)
            }
            didMutate = true
        }

        if didMutate {
            try modelContext.save()
        }
    }

    static func ensureSystemCategory(
        _ systemKey: MistiaSystemCategoryKey,
        modelContext: ModelContext
    ) throws -> TransactionCategory {
        try seedDefaultCategoriesIfNeeded(modelContext: modelContext)

        let existingCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            .filter { $0.deletedAt == nil }
        if let existing = existingCategories.first(where: { $0.systemKey == systemKey.rawValue }) {
            return existing
        }

        guard let seed = ManagementPresetData.defaultCategorySeeds.first(where: { $0.systemKey == systemKey }) else {
            fatalError("Missing seed for system category \(systemKey.rawValue)")
        }

        let category = TransactionCategory(
            name: seed.name,
            kind: seed.kind,
            iconSymbolName: seed.iconSymbolName,
            iconColorHex: seed.iconColorHex,
            systemKey: systemKey.rawValue,
            isSystem: true,
            sortOrder: 0,
            isArchived: seed.startsArchived
        )
        modelContext.insert(category)
        try modelContext.save()
        return category
    }

    private static func nextSortOrder(
        for kind: TransactionCategoryKind,
        categories: [TransactionCategory]
    ) -> Int {
        let visible = categories
            .filter { !$0.isArchived && $0.kind == kind }
            .map(\.sortOrder)
            .max() ?? -1

        return visible + 1
    }

    private static func normalizeLegacyDefaultIconColors(
        categories: [TransactionCategory],
        wallets: [LedgerWallet]
    ) -> Bool {
        var didMutate = false

        for wallet in wallets {
            guard let migratedColorHex = wallet.kind.migratedLegacyDefaultColorHex(
                for: wallet.iconColorHex,
                symbolName: wallet.iconSymbolName
            ) else {
                continue
            }

            wallet.iconColorHex = migratedColorHex
            wallet.updatedAt = .now
            didMutate = true
        }

        for category in categories where !category.isSystem && category.systemKey == nil {
            guard let migratedColorHex = category.kind.migratedLegacyDefaultColorHex(
                for: category.iconColorHex,
                symbolName: category.iconSymbolName
            ) else {
                continue
            }

            category.iconColorHex = migratedColorHex
            category.updatedAt = .now
            didMutate = true
        }

        return didMutate
    }
}
