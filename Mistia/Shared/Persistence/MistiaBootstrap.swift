import SwiftData

enum MistiaBootstrap {
    static func seedDefaultCategoriesIfNeeded(modelContext: ModelContext) throws {
        let existingCount = try modelContext.fetchCount(FetchDescriptor<TransactionCategory>())
        guard existingCount == 0 else { return }

        for (index, seed) in ManagementPresetData.defaultCategorySeeds.enumerated() {
            let category = TransactionCategory(
                name: seed.name,
                kind: seed.kind,
                iconSymbolName: seed.iconSymbolName,
                iconColorHex: seed.iconColorHex,
                isSystem: true,
                sortOrder: index
            )
            modelContext.insert(category)
        }

        try modelContext.save()
    }
}
