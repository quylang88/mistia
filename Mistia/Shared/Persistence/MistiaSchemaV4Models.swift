import Foundation
import SwiftData

enum MistiaSchemaV4Models {
    @Model
    final class LedgerWallet {
        @Attribute(.unique) var id: UUID
        var name: String
        var kindRawValue: String
        var iconSymbolName: String
        var iconColorHex: String
        var currencyCode: String
        var openingBalanceMinor: Int64
        var institutionDisplayName: String?
        var institutionPresetKey: String?
        var sortOrder: Int
        var isArchived: Bool
        var archivedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64
        var creditCardProfile: CreditCardProfile?

        init(
            id: UUID = UUID(),
            name: String = "",
            kindRawValue: String = LedgerWalletKind.cash.rawValue,
            iconSymbolName: String = LedgerWalletKind.cash.defaultIconSymbolName,
            iconColorHex: String = LedgerWalletKind.cash.defaultColorHex,
            currencyCode: String = "JPY",
            openingBalanceMinor: Int64 = 0,
            institutionDisplayName: String? = nil,
            institutionPresetKey: String? = nil,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0,
            creditCardProfile: CreditCardProfile? = nil
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.iconSymbolName = iconSymbolName
            self.iconColorHex = iconColorHex
            self.currencyCode = currencyCode
            self.openingBalanceMinor = openingBalanceMinor
            self.institutionDisplayName = institutionDisplayName
            self.institutionPresetKey = institutionPresetKey
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
            self.creditCardProfile = creditCardProfile
        }
    }

    @Model
    final class CreditCardProfile {
        @Attribute(.unique) var id: UUID
        var issuerName: String
        var networkRawValue: String
        var last4: String
        var creditLimitMinor: Int64
        var statementClosingDay: Int
        var paymentDueDay: Int
        var notes: String?
        var autoPayEnabled: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64
        var wallet: LedgerWallet?
        var paymentSourceWallet: LedgerWallet?

        init(
            id: UUID = UUID(),
            issuerName: String = "",
            networkRawValue: String = CreditCardNetwork.visa.rawValue,
            last4: String = "",
            creditLimitMinor: Int64 = 0,
            statementClosingDay: Int = 25,
            paymentDueDay: Int = 10,
            notes: String? = nil,
            autoPayEnabled: Bool = true,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0,
            wallet: LedgerWallet? = nil,
            paymentSourceWallet: LedgerWallet? = nil
        ) {
            self.id = id
            self.issuerName = issuerName
            self.networkRawValue = networkRawValue
            self.last4 = last4
            self.creditLimitMinor = creditLimitMinor
            self.statementClosingDay = statementClosingDay
            self.paymentDueDay = paymentDueDay
            self.notes = notes
            self.autoPayEnabled = autoPayEnabled
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
            self.wallet = wallet
            self.paymentSourceWallet = paymentSourceWallet
        }
    }

    @Model
    final class TransactionCategory {
        @Attribute(.unique) var id: UUID
        var name: String
        var nameEnglish: String?
        var nameJapanese: String?
        var pendingTranslationSourceName: String?
        var pendingTranslationSourceLanguageRawValue: String?
        var kindRawValue: String
        var iconSymbolName: String
        var iconColorHex: String
        var favoriteRawValue: Bool?
        var familyBudgetSpendingEnabledRawValue: Bool?
        var parentCategory: TransactionCategory?
        @Relationship(deleteRule: .nullify, inverse: \TransactionCategory.parentCategory) var childCategories: [TransactionCategory]
        var hierarchyRoleRawValue: String?
        var systemKey: String?
        var isSystem: Bool
        var cloudSyncEnabled: Bool
        var sortOrder: Int
        var isArchived: Bool
        var archivedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String = "",
            nameEnglish: String? = nil,
            nameJapanese: String? = nil,
            pendingTranslationSourceName: String? = nil,
            pendingTranslationSourceLanguageRawValue: String? = nil,
            kindRawValue: String = TransactionCategoryKind.expense.rawValue,
            iconSymbolName: String = "circle.fill",
            iconColorHex: String = "#8E8E93",
            favoriteRawValue: Bool? = false,
            familyBudgetSpendingEnabledRawValue: Bool? = false,
            parentCategory: TransactionCategory? = nil,
            childCategories: [TransactionCategory] = [],
            hierarchyRoleRawValue: String? = nil,
            systemKey: String? = nil,
            isSystem: Bool = false,
            cloudSyncEnabled: Bool = false,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.nameEnglish = nameEnglish
            self.nameJapanese = nameJapanese
            self.pendingTranslationSourceName = pendingTranslationSourceName
            self.pendingTranslationSourceLanguageRawValue = pendingTranslationSourceLanguageRawValue
            self.kindRawValue = kindRawValue
            self.iconSymbolName = iconSymbolName
            self.iconColorHex = iconColorHex
            self.favoriteRawValue = favoriteRawValue
            self.familyBudgetSpendingEnabledRawValue = familyBudgetSpendingEnabledRawValue
            self.parentCategory = parentCategory
            self.childCategories = childCategories
            self.hierarchyRoleRawValue = hierarchyRoleRawValue
            self.systemKey = systemKey
            self.isSystem = isSystem
            self.cloudSyncEnabled = cloudSyncEnabled
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class LedgerTransaction {
        @Attribute(.unique) var id: UUID
        var primaryKindRawValue: String
        var transferSubtypeRawValue: String?
        var debtIntentRawValue: String?
        var entryStatusRawValue: String
        var title: String
        var note: String?
        var amountMinor: Int64
        var sourceCurrencyCode: String?
        var destinationCurrencyCode: String?
        var destinationAmountMinor: Int64?
        var reportingCurrencyCode: String?
        var reportingAmountMinor: Int64?
        var conversionModeRawValue: String?
        var exchangeRateDecimalString: String?
        var exchangeRateProvider: String?
        var exchangeRateDate: String?
        var occurredAt: Date
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64
        var counterpartyName: String?
        var normalizedCounterpartyKey: String?
        var isArchived: Bool
        var archivedAt: Date?
        @Relationship(deleteRule: .nullify) var sourceWallet: LedgerWallet?
        @Relationship(deleteRule: .nullify) var destinationWallet: LedgerWallet?
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?

        init(
            id: UUID = UUID(),
            primaryKindRawValue: String = TransactionPrimaryKind.expense.rawValue,
            transferSubtypeRawValue: String? = nil,
            debtIntentRawValue: String? = nil,
            entryStatusRawValue: String = TransactionEntryStatus.posted.rawValue,
            title: String = "",
            note: String? = nil,
            amountMinor: Int64 = 0,
            sourceCurrencyCode: String? = nil,
            destinationCurrencyCode: String? = nil,
            destinationAmountMinor: Int64? = nil,
            reportingCurrencyCode: String? = nil,
            reportingAmountMinor: Int64? = nil,
            conversionModeRawValue: String? = nil,
            exchangeRateDecimalString: String? = nil,
            exchangeRateProvider: String? = nil,
            exchangeRateDate: String? = nil,
            occurredAt: Date = .now,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0,
            counterpartyName: String? = nil,
            normalizedCounterpartyKey: String? = nil,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            sourceWallet: LedgerWallet? = nil,
            destinationWallet: LedgerWallet? = nil,
            category: TransactionCategory? = nil
        ) {
            self.id = id
            self.primaryKindRawValue = primaryKindRawValue
            self.transferSubtypeRawValue = transferSubtypeRawValue
            self.debtIntentRawValue = debtIntentRawValue
            self.entryStatusRawValue = entryStatusRawValue
            self.title = title
            self.note = note
            self.amountMinor = amountMinor
            self.sourceCurrencyCode = sourceCurrencyCode
            self.destinationCurrencyCode = destinationCurrencyCode
            self.destinationAmountMinor = destinationAmountMinor
            self.reportingCurrencyCode = reportingCurrencyCode
            self.reportingAmountMinor = reportingAmountMinor
            self.conversionModeRawValue = conversionModeRawValue
            self.exchangeRateDecimalString = exchangeRateDecimalString
            self.exchangeRateProvider = exchangeRateProvider
            self.exchangeRateDate = exchangeRateDate
            self.occurredAt = occurredAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
            self.counterpartyName = counterpartyName
            self.normalizedCounterpartyKey = normalizedCounterpartyKey
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.sourceWallet = sourceWallet
            self.destinationWallet = destinationWallet
            self.category = category
        }
    }

    @Model
    final class TransactionReceiptImage {
        @Attribute(.unique) var id: UUID
        var transactionID: UUID
        var imageFileName: String
        var thumbnailFileName: String
        var contentType: String
        var byteCount: Int
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            transactionID: UUID = UUID(),
            imageFileName: String = "",
            thumbnailFileName: String = "",
            contentType: String = "image/jpeg",
            byteCount: Int = 0,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.transactionID = transactionID
            self.imageFileName = imageFileName
            self.thumbnailFileName = thumbnailFileName
            self.contentType = contentType
            self.byteCount = byteCount
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class BudgetPlan {
        @Attribute(.unique) var id: UUID
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?
        var categoryIDSnapshot: UUID?
        var categoryNameSnapshot: String?
        var categoryNameEnglishSnapshot: String?
        var categoryNameJapaneseSnapshot: String?
        var categoryPathSnapshot: String?
        var categoryPathEnglishSnapshot: String?
        var categoryPathJapaneseSnapshot: String?
        var categoryIconSymbolNameSnapshot: String?
        var categoryColorHexSnapshot: String?
        var categoryParentIDSnapshot: UUID?
        var categoryParentNameSnapshot: String?
        var categoryParentNameEnglishSnapshot: String?
        var categoryParentNameJapaneseSnapshot: String?
        var categoryParentIconSymbolNameSnapshot: String?
        var categoryParentColorHexSnapshot: String?
        var categoryHierarchyRoleSnapshotRawValue: String?
        var categoryIsParentSnapshotRawValue: Bool?
        var includesFamilySpendingRawValue: Bool?
        var monthAnchor: Date
        var limitMinor: Int64
        var rolloverEnabled: Bool
        var currencyCode: String
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            category: TransactionCategory? = nil,
            categoryIDSnapshot: UUID? = nil,
            categoryNameSnapshot: String? = nil,
            categoryNameEnglishSnapshot: String? = nil,
            categoryNameJapaneseSnapshot: String? = nil,
            categoryPathSnapshot: String? = nil,
            categoryPathEnglishSnapshot: String? = nil,
            categoryPathJapaneseSnapshot: String? = nil,
            categoryIconSymbolNameSnapshot: String? = nil,
            categoryColorHexSnapshot: String? = nil,
            categoryParentIDSnapshot: UUID? = nil,
            categoryParentNameSnapshot: String? = nil,
            categoryParentNameEnglishSnapshot: String? = nil,
            categoryParentNameJapaneseSnapshot: String? = nil,
            categoryParentIconSymbolNameSnapshot: String? = nil,
            categoryParentColorHexSnapshot: String? = nil,
            categoryHierarchyRoleSnapshotRawValue: String? = nil,
            categoryIsParentSnapshotRawValue: Bool? = nil,
            includesFamilySpendingRawValue: Bool? = false,
            monthAnchor: Date = .now,
            limitMinor: Int64 = 0,
            rolloverEnabled: Bool = false,
            currencyCode: String = "JPY",
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.category = category
            self.categoryIDSnapshot = categoryIDSnapshot
            self.categoryNameSnapshot = categoryNameSnapshot
            self.categoryNameEnglishSnapshot = categoryNameEnglishSnapshot
            self.categoryNameJapaneseSnapshot = categoryNameJapaneseSnapshot
            self.categoryPathSnapshot = categoryPathSnapshot
            self.categoryPathEnglishSnapshot = categoryPathEnglishSnapshot
            self.categoryPathJapaneseSnapshot = categoryPathJapaneseSnapshot
            self.categoryIconSymbolNameSnapshot = categoryIconSymbolNameSnapshot
            self.categoryColorHexSnapshot = categoryColorHexSnapshot
            self.categoryParentIDSnapshot = categoryParentIDSnapshot
            self.categoryParentNameSnapshot = categoryParentNameSnapshot
            self.categoryParentNameEnglishSnapshot = categoryParentNameEnglishSnapshot
            self.categoryParentNameJapaneseSnapshot = categoryParentNameJapaneseSnapshot
            self.categoryParentIconSymbolNameSnapshot = categoryParentIconSymbolNameSnapshot
            self.categoryParentColorHexSnapshot = categoryParentColorHexSnapshot
            self.categoryHierarchyRoleSnapshotRawValue = categoryHierarchyRoleSnapshotRawValue
            self.categoryIsParentSnapshotRawValue = categoryIsParentSnapshotRawValue
            self.includesFamilySpendingRawValue = includesFamilySpendingRawValue
            self.monthAnchor = monthAnchor
            self.limitMinor = limitMinor
            self.rolloverEnabled = rolloverEnabled
            self.currencyCode = currencyCode
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class SavingsGoal {
        @Attribute(.unique) var id: UUID
        var name: String
        var iconSymbolName: String
        var targetMinor: Int64
        var currentSavedMinor: Int64
        var targetDate: Date
        @Relationship(deleteRule: .nullify) var linkedWallet: LedgerWallet?
        var currencyCode: String
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String = "",
            iconSymbolName: String = "target",
            targetMinor: Int64 = 0,
            currentSavedMinor: Int64 = 0,
            targetDate: Date = .now,
            linkedWallet: LedgerWallet? = nil,
            currencyCode: String = "JPY",
            sortOrder: Int = 0,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.iconSymbolName = iconSymbolName
            self.targetMinor = targetMinor
            self.currentSavedMinor = currentSavedMinor
            self.targetDate = targetDate
            self.linkedWallet = linkedWallet
            self.currencyCode = currencyCode
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class RecurringBillPlan {
        @Attribute(.unique) var id: UUID
        var name: String
        var iconSymbolName: String
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?
        var amountMinor: Int64?
        var dueDay: Int
        var scheduleKindRawValue: String?
        var paymentStartDay: Int?
        var paymentStartDate: Date?
        var firstScheduledMonth: Date?
        var hasExplicitDueDate: Bool?
        var dueDate: Date?
        var autoPayEnabled: Bool
        var autoPayDay: Int?
        var autoPayDate: Date?
        var frequencyMonths: Int
        @Relationship(deleteRule: .nullify) var paymentWallet: LedgerWallet?
        var currencyCode: String
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String = "",
            iconSymbolName: String = "calendar",
            category: TransactionCategory? = nil,
            amountMinor: Int64? = nil,
            dueDay: Int = 1,
            scheduleKindRawValue: String? = PlanningBillScheduleKind.recurring.rawValue,
            paymentStartDay: Int? = nil,
            paymentStartDate: Date? = nil,
            firstScheduledMonth: Date? = nil,
            hasExplicitDueDate: Bool? = false,
            dueDate: Date? = nil,
            autoPayEnabled: Bool = false,
            autoPayDay: Int? = nil,
            autoPayDate: Date? = nil,
            frequencyMonths: Int = 1,
            paymentWallet: LedgerWallet? = nil,
            currencyCode: String = "JPY",
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.iconSymbolName = iconSymbolName
            self.category = category
            self.amountMinor = amountMinor
            self.dueDay = dueDay
            self.scheduleKindRawValue = scheduleKindRawValue
            self.paymentStartDay = paymentStartDay
            self.paymentStartDate = paymentStartDate
            self.firstScheduledMonth = firstScheduledMonth
            self.hasExplicitDueDate = hasExplicitDueDate
            self.dueDate = dueDate
            self.autoPayEnabled = autoPayEnabled
            self.autoPayDay = autoPayDay
            self.autoPayDate = autoPayDate
            self.frequencyMonths = frequencyMonths
            self.paymentWallet = paymentWallet
            self.currencyCode = currencyCode
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class InstallmentPlan {
        @Attribute(.unique) var id: UUID
        var name: String
        var iconSymbolName: String
        var amountPerCycleMinor: Int64
        var dueDay: Int
        var totalCycles: Int?
        var frequencyMonths: Int
        @Relationship(deleteRule: .nullify) var paymentWallet: LedgerWallet?
        var currencyCode: String
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String = "",
            iconSymbolName: String = "creditcard.and.123",
            amountPerCycleMinor: Int64 = 0,
            dueDay: Int = 1,
            totalCycles: Int? = nil,
            frequencyMonths: Int = 1,
            paymentWallet: LedgerWallet? = nil,
            currencyCode: String = "JPY",
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.iconSymbolName = iconSymbolName
            self.amountPerCycleMinor = amountPerCycleMinor
            self.dueDay = dueDay
            self.totalCycles = totalCycles
            self.frequencyMonths = frequencyMonths
            self.paymentWallet = paymentWallet
            self.currencyCode = currencyCode
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class DueOccurrenceRecord {
        @Attribute(.unique) var id: UUID
        var sourceKindRawValue: String
        var sourceID: UUID
        var selectedMonthKey: String
        var scheduledDate: Date
        var amountMinorSnapshot: Int64?
        var statusRawValue: String
        var paidAt: Date?
        var linkedTransactionID: UUID?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            sourceKindRawValue: String = PlanningDueSourceKind.recurringBill.rawValue,
            sourceID: UUID = UUID(),
            selectedMonthKey: String = "",
            scheduledDate: Date = .now,
            amountMinorSnapshot: Int64? = nil,
            statusRawValue: String = PlanningDueOccurrenceStatus.pending.rawValue,
            paidAt: Date? = nil,
            linkedTransactionID: UUID? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.sourceKindRawValue = sourceKindRawValue
            self.sourceID = sourceID
            self.selectedMonthKey = selectedMonthKey
            self.scheduledDate = scheduledDate
            self.amountMinorSnapshot = amountMinorSnapshot
            self.statusRawValue = statusRawValue
            self.paidAt = paidAt
            self.linkedTransactionID = linkedTransactionID
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class AppNotificationRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var key: String
        var createdAt: Date
        var updatedAt: Date
        var title: String
        var body: String
        var kindRawValue: String
        var sourceRawValue: String
        var isRead: Bool
        var actionRoute: String?
        var recipientUserID: UUID?
        var actorUserID: UUID?
        var familyID: UUID?
        var resourceTypeRawValue: String?
        var resourceID: UUID?
        var permissionScopeRawValue: String?
        var permissionRequestID: UUID?
        var actionStateRawValue: String?
        var readAt: Date?
        var metadataJSON: String?
        var remoteVersion: Int64
        var needsReadSync: Bool

        init(
            id: UUID = UUID(),
            key: String = "",
            createdAt: Date = .now,
            updatedAt: Date = .now,
            title: String = "",
            body: String = "",
            kindRawValue: String = MistiaAppNotificationKind.dueSoon.rawValue,
            sourceRawValue: String = MistiaAppNotificationSource.system.rawValue,
            isRead: Bool = false,
            actionRoute: String? = nil,
            recipientUserID: UUID? = nil,
            actorUserID: UUID? = nil,
            familyID: UUID? = nil,
            resourceTypeRawValue: String? = nil,
            resourceID: UUID? = nil,
            permissionScopeRawValue: String? = nil,
            permissionRequestID: UUID? = nil,
            actionStateRawValue: String? = nil,
            readAt: Date? = nil,
            metadataJSON: String? = nil,
            remoteVersion: Int64 = 0,
            needsReadSync: Bool = false
        ) {
            self.id = id
            self.key = key
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.title = title
            self.body = body
            self.kindRawValue = kindRawValue
            self.sourceRawValue = sourceRawValue
            self.isRead = isRead
            self.actionRoute = actionRoute
            self.recipientUserID = recipientUserID
            self.actorUserID = actorUserID
            self.familyID = familyID
            self.resourceTypeRawValue = resourceTypeRawValue
            self.resourceID = resourceID
            self.permissionScopeRawValue = permissionScopeRawValue
            self.permissionRequestID = permissionRequestID
            self.actionStateRawValue = actionStateRawValue
            self.readAt = readAt
            self.metadataJSON = metadataJSON
            self.remoteVersion = remoteVersion
            self.needsReadSync = needsReadSync
        }
    }

    @Model
    final class SyncConflict {
        @Attribute(.unique) var id: UUID
        var entityRawValue: String
        var recordID: UUID
        var conflictKindRawValue: String
        var localPayloadJSON: String
        var remotePayloadJSON: String
        var baseVersion: Int64
        var remoteVersion: Int64
        var createdAt: Date

        init(
            id: UUID = UUID(),
            entityRawValue: String = "",
            recordID: UUID = UUID(),
            conflictKindRawValue: String = "",
            localPayloadJSON: String = "",
            remotePayloadJSON: String = "",
            baseVersion: Int64 = 0,
            remoteVersion: Int64 = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.entityRawValue = entityRawValue
            self.recordID = recordID
            self.conflictKindRawValue = conflictKindRawValue
            self.localPayloadJSON = localPayloadJSON
            self.remotePayloadJSON = remotePayloadJSON
            self.baseVersion = baseVersion
            self.remoteVersion = remoteVersion
            self.createdAt = createdAt
        }
    }

    @Model
    final class UserAccountProfile {
        @Attribute(.unique) var userID: UUID
        var email: String
        var displayName: String
        var avatarFileName: String?
        var birthday: Date?
        var lastSyncAt: Date?
        var createdAt: Date
        var updatedAt: Date

        init(
            userID: UUID = UUID(),
            email: String = "",
            displayName: String = "",
            avatarFileName: String? = nil,
            birthday: Date? = nil,
            lastSyncAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.userID = userID
            self.email = email
            self.displayName = displayName
            self.avatarFileName = avatarFileName
            self.birthday = birthday
            self.lastSyncAt = lastSyncAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class OwnedRecordScope {
        @Attribute(.unique) var id: String
        var entityRawValue: String
        var recordID: UUID
        var ownerUserID: UUID
        var updatedAt: Date

        init(
            id: String = "",
            entityRawValue: String = "",
            recordID: UUID = UUID(),
            ownerUserID: UUID = UUID(),
            updatedAt: Date = .now
        ) {
            self.id = id.isEmpty
                ? "\(entityRawValue):\(recordID.uuidString.lowercased())"
                : id
            self.entityRawValue = entityRawValue
            self.recordID = recordID
            self.ownerUserID = ownerUserID
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class TransactionAuditRecord {
        @Attribute(.unique) var transactionID: UUID
        var createdByUserID: UUID
        var lastModifiedByUserID: UUID
        var updatedAt: Date

        init(
            transactionID: UUID = UUID(),
            createdByUserID: UUID = UUID(),
            lastModifiedByUserID: UUID = UUID(),
            updatedAt: Date = .now
        ) {
            self.transactionID = transactionID
            self.createdByUserID = createdByUserID
            self.lastModifiedByUserID = lastModifiedByUserID
            self.updatedAt = updatedAt
        }
    }
}
