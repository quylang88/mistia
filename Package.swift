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
                "Sync/ReceiptAnalysisService.swift",
                "Sync/SupabaseAuthService.swift",
                "Sync/SupabaseRemoteStore.swift",
                "Sync/SupabaseUserProfileStore.swift"
            ],
            sources: [
                "CoreLogic/CurrencyFormatting.swift",
                "CoreLogic/FamilyLogic.swift",
                "CoreLogic/FinanceEnums.swift",
                "CoreLogic/MistiaLocalization.swift",
                "CoreLogic/MistiaResetSupport.swift",
                "CoreLogic/MistiaShortcutLogic.swift",
                "CoreLogic/MistiaSystemCategoryIdentity.swift",
                "CoreLogic/OverviewLogic.swift",
                "CoreLogic/PlanningLogic.swift",
                "CoreLogic/ReceiptAnalysisModels.swift",
                "CoreLogic/TransactionLogic.swift",
                "CoreLogic/TransactionLogic+Statement.swift",
                "Persistence/CategoryHierarchySupport.swift",
                "Persistence/ManagementModels.swift",
                "Persistence/MistiaDataStack.swift",
                "Persistence/MistiaLocalProfiles.swift",
                "Persistence/MistiaMigration.swift",
                "Persistence/NotificationModels.swift",
                "Persistence/TransactionReceiptImageStore.swift",
                "Persistence/MistiaRecordOwnership.swift",
                "Persistence/PlanningModels.swift",
                "Persistence/SyncConflictModel.swift",
                "Persistence/TransactionAuditModels.swift",
                "Persistence/UserProfileModels.swift",
                "Sync/MistiaSyncLocalStore.swift",
                "Sync/MistiaSyncModels.swift",
                "Sync/MistiaSyncOutbox.swift",
                "Sync/MistiaSyncSupport.swift",
                "Sync/MistiaSystemCategorySyncSupport.swift"
            ]
        ),
        .testTarget(
            name: "MistiaCoreLogicTests",
            dependencies: ["MistiaCoreLogic"]
        ),
        .testTarget(
            name: "MistiaDataSupportTests",
            dependencies: ["MistiaCoreLogic"]
        )
    ]
)
