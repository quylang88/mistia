import Foundation
import SwiftData

enum MistiaBootstrap {
    static func cleanupExpiredArchivedData(
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) throws {
        let thresholdDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        var didDelete = false

        var txDescriptor = FetchDescriptor<LedgerTransaction>()
        txDescriptor.predicate = #Predicate<LedgerTransaction> { $0.isArchived == true }
        for transaction in try modelContext.fetch(txDescriptor) {
            if let archivedAt = transaction.archivedAt, archivedAt < thresholdDate {
                let id = transaction.id
                modelContext.delete(transaction)
                sessionStore.recordDelete(entity: .transaction, recordID: id, modifiedAt: .now)
                didDelete = true
            }
        }

        var walletDescriptor = FetchDescriptor<LedgerWallet>()
        walletDescriptor.predicate = #Predicate<LedgerWallet> { $0.isArchived == true }
        for wallet in try modelContext.fetch(walletDescriptor) {
            if let archivedAt = wallet.archivedAt, archivedAt < thresholdDate {
                let id = wallet.id
                modelContext.delete(wallet)
                sessionStore.recordDelete(entity: .wallet, recordID: id, modifiedAt: .now)
                didDelete = true
            }
        }

        var categoryDescriptor = FetchDescriptor<TransactionCategory>()
        categoryDescriptor.predicate = #Predicate<TransactionCategory> { $0.isArchived == true }
        for category in try modelContext.fetch(categoryDescriptor) {
            if let archivedAt = category.archivedAt, archivedAt < thresholdDate {
                let id = category.id
                modelContext.delete(category)
                sessionStore.recordDelete(entity: .category, recordID: id, modifiedAt: .now)
                didDelete = true
            }
        }

        if didDelete {
            try modelContext.save()
        }
    }

    static func seedDefaultCategoriesIfNeeded(modelContext: ModelContext) throws {
        let existingCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
        let existingWallets = try modelContext.fetch(FetchDescriptor<LedgerWallet>())
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
        } else {
            if let legacyOtherIncome = existingCategories.first(where: {
                $0.isSystem
                    && $0.kind == .income
                    && $0.name.localizedCaseInsensitiveCompare("Khác") == .orderedSame
            }), !existingCategories.contains(where: {
                $0.kind == .income
                    && $0.name.localizedCaseInsensitiveCompare("Phụ cấp") == .orderedSame
            }) {
                legacyOtherIncome.name = "Phụ cấp"
                legacyOtherIncome.iconSymbolName = "wallet.pass.fill"
                legacyOtherIncome.iconColorHex = "#9A67FF"
                legacyOtherIncome.updatedAt = .now
                didMutate = true
            }

            for seed in ManagementPresetData.defaultCategorySeeds {
                if let systemKey = seed.systemKey,
                   let matchedCategory = existingCategories.first(where: {
                       $0.systemKey == systemKey.rawValue
                           || ($0.name.localizedCaseInsensitiveCompare(seed.name) == .orderedSame && $0.kind == seed.kind)
                   }) {
                    var didMutateCategory = false
                    if matchedCategory.name != seed.name {
                        matchedCategory.name = seed.name
                        didMutateCategory = true
                    }
                    if matchedCategory.iconSymbolName != seed.iconSymbolName {
                        matchedCategory.iconSymbolName = seed.iconSymbolName
                        didMutateCategory = true
                    }
                    if matchedCategory.iconColorHex != seed.iconColorHex {
                        matchedCategory.iconColorHex = seed.iconColorHex
                        didMutateCategory = true
                    }
                    if matchedCategory.systemKey != systemKey.rawValue {
                        matchedCategory.systemKey = systemKey.rawValue
                        didMutateCategory = true
                    }
                    if !matchedCategory.isSystem {
                        matchedCategory.isSystem = true
                        didMutateCategory = true
                    }
                    if didMutateCategory {
                        matchedCategory.updatedAt = .now
                        didMutate = true
                    }
                    continue
                }

                if existingCategories.contains(where: {
                    $0.name.localizedCaseInsensitiveCompare(seed.name) == .orderedSame && $0.kind == seed.kind
                }) {
                    continue
                }

                let category = TransactionCategory(
                    name: seed.name,
                    kind: seed.kind,
                    iconSymbolName: seed.iconSymbolName,
                    iconColorHex: seed.iconColorHex,
                    systemKey: seed.systemKey?.rawValue,
                    isSystem: true,
                    sortOrder: nextSortOrder(for: seed.kind, categories: existingCategories),
                    isArchived: seed.startsArchived
                )
                modelContext.insert(category)
                didMutate = true
            }
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
