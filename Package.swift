// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MistiaCoreLogic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MistiaCoreLogic",
            targets: ["MistiaCoreLogic"]
        ),
        .library(
            name: "MistiaDataSupport",
            targets: ["MistiaCoreLogic"]
        )
    ],
    targets: [
        .target(
            name: "MistiaCoreLogic",
            path: "Mistia/Shared",
            exclude: [
                "Family",
                "Models",
                "Modifiers",
                "Notifications",
                "Session",
                "Styles",
                "Persistence/MistiaBootstrap.swift",
                "Persistence/MistiaLegacyStoreRecovery.swift",
                "Sync/CategoryNameTranslationService.swift",
                "Sync/KeychainStore.swift",
                "Sync/MistiaGoogleSignInConfiguration.swift",
                "Sync/MistiaSyncBackgroundScheduler.swift",
                "Sync/MistiaSyncConfiguration.swift",
                "Sync/MistiaSyncCoordinator.swift",
                "Sync/BillItemAnalysisService.swift",
                "Sync/ReceiptAnalysisService.swift",
                "Sync/SupabaseAuthService.swift",
                "Sync/SupabaseRemoteStore.swift",
                "Sync/SupabaseUserProfileStore.swift"
            ],
            sources: [
                "CoreLogic/CurrencyFormatting.swift",
                "CoreLogic/CurrencyLogic.swift",
                "CoreLogic/FamilyLogic.swift",
                "CoreLogic/FinanceEnums.swift",
                "CoreLogic/InvestmentLogic.swift",
                "CoreLogic/FamilyOverviewVisibility.swift",
                "CoreLogic/BillItemAnalysisModels.swift",
                "CoreLogic/L10n.generated.swift",
                "CoreLogic/MistiaAmountCalculatorLogic.swift",
                "CoreLogic/MistiaAppLockLogic.swift",
                "CoreLogic/MistiaArchiveRetention.swift",
                "CoreLogic/MistiaCollectionChangeSignature.swift",
                "CoreLogic/MistiaUnsavedChangesDismissalLogic.swift",
                "CoreLogic/FamilyOverviewCalculator.swift",
                "CoreLogic/MistiaLocalization.swift",
                "CoreLogic/MistiaCalendarSelectionLogic.swift",
                "CoreLogic/MistiaResetSupport.swift",
                "CoreLogic/MistiaShortcutLogic.swift",
                "CoreLogic/MistiaSyncConflictPresentation.swift",
                "CoreLogic/MistiaSystemCategoryIdentity.swift",
                "CoreLogic/MistiaSystemCategoryRegistry.swift",
                "CoreLogic/MistiaWalletPickerAccessLogic.swift",
                "CoreLogic/OverviewLogic.swift",
                "CoreLogic/PlanningLogic.swift",
                "CoreLogic/ReceiptAnalysisModels.swift",
                "CoreLogic/TransactionLogic.swift",
                "CoreLogic/TransactionLogic+Statement.swift",
                "CoreLogic/TransactionGeneratedTitle.swift",
                "CoreLogic/TransactionSearchLogic.swift",
                "Feedback/FeedbackPromptCoordinator.swift",
                "Persistence/CategoryHierarchySupport.swift",
                "Persistence/InvestmentModels.swift",
                "Persistence/InvestmentPersistence.swift",
                "Persistence/ManagementModels.swift",
                "Persistence/MistiaDataStack.swift",
                "Persistence/MistiaLocalProfiles.swift",
                "Persistence/MistiaMigration.swift",
                "Persistence/MistiaSchemaV4Models.swift",
                "Persistence/MistiaSchemaV5Models.swift",
                "Persistence/NotificationModels.swift",
                "Persistence/TransactionReceiptImageStore.swift",
                "Persistence/MistiaRecordOwnership.swift",
                "Persistence/PlanningModels.swift",
                "Persistence/SyncConflictModel.swift",
                "Persistence/TransactionAuditModels.swift",
                "Persistence/UserProfileModels.swift",
                "Sync/MistiaSyncLocalStore.swift",
                "Sync/InvestmentSyncModels.swift",
                "Sync/MistiaSyncModels.swift",
                "Sync/MistiaSyncOutbox.swift",
                "Sync/MistiaSyncSupport.swift",
                "Sync/MistiaSystemCategorySyncSupport.swift"
            ],
            resources: [
                .process("CoreLogic/MistiaSystemCategories.json")
            ]
        ),
        .testTarget(
            name: "MistiaCoreLogicTests",
            dependencies: ["MistiaCoreLogic"]
        ),
        .testTarget(
            name: "MistiaTests",
            dependencies: ["MistiaCoreLogic"],
            path: "MistiaTests",
            sources: ["FeedbackPromptCoordinatorTests.swift"]
        ),
        .testTarget(
            name: "MistiaDataSupportTests",
            dependencies: ["MistiaCoreLogic"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
