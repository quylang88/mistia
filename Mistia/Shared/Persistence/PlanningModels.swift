import Foundation
import SwiftData

let recurringBillPausedScheduleKindRawValue = "pausedRecurring"

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
        includesFamilySpending: Bool = false,
        monthAnchor: Date,
        limitMinor: Int64,
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
        self.includesFamilySpendingRawValue = includesFamilySpending
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

    var includesFamilySpending: Bool {
        get { includesFamilySpendingRawValue ?? false }
        set { includesFamilySpendingRawValue = newValue }
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
        name: String,
        iconSymbolName: String,
        targetMinor: Int64,
        currentSavedMinor: Int64 = 0,
        targetDate: Date,
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
    var autoPayEnabled: Bool = false
    var autoPayDay: Int?
    var autoPayDate: Date?
    var frequencyMonths: Int
    @Relationship(deleteRule: .nullify) var paymentWallet: LedgerWallet?
    var currencyCode: String
    var isArchived: Bool
    var isPaused: Bool = false
    var pausedAt: Date?
    var resumeStartMonth: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var remoteVersion: Int64

    init(
        id: UUID = UUID(),
        name: String,
        iconSymbolName: String,
        category: TransactionCategory? = nil,
        amountMinor: Int64? = nil,
        dueDay: Int,
        scheduleKind: PlanningBillScheduleKind = .recurring,
        paymentStartDay: Int? = nil,
        paymentStartDate: Date? = nil,
        firstScheduledMonth: Date? = nil,
        hasExplicitDueDate: Bool? = nil,
        dueDate: Date? = nil,
        autoPayEnabled: Bool = false,
        autoPayDay: Int? = nil,
        autoPayDate: Date? = nil,
        frequencyMonths: Int = 1,
        paymentWallet: LedgerWallet? = nil,
        currencyCode: String = "JPY",
        isArchived: Bool = false,
        isPaused: Bool = false,
        pausedAt: Date? = nil,
        resumeStartMonth: Date? = nil,
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
        self.scheduleKindRawValue = scheduleKind.rawValue
        self.paymentStartDay = paymentStartDay ?? dueDay
        self.paymentStartDate = paymentStartDate
        self.firstScheduledMonth = firstScheduledMonth
        self.hasExplicitDueDate = hasExplicitDueDate ?? false
        self.dueDate = dueDate
        self.autoPayEnabled = autoPayEnabled
        self.autoPayDay = autoPayDay
        self.autoPayDate = autoPayDate
        self.frequencyMonths = frequencyMonths
        self.paymentWallet = paymentWallet
        self.currencyCode = currencyCode
        self.isArchived = isArchived
        if scheduleKind == .recurring {
            self.isPaused = isPaused
            self.pausedAt = isPaused ? pausedAt : nil
            self.resumeStartMonth = resumeStartMonth
        } else {
            self.isPaused = false
            self.pausedAt = nil
            self.resumeStartMonth = nil
        }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
    }

    var scheduleKind: PlanningBillScheduleKind {
        get {
            if scheduleKindRawValue == recurringBillPausedScheduleKindRawValue {
                return .recurring
            }
            return PlanningBillScheduleKind(rawValue: scheduleKindRawValue ?? "") ?? .recurring
        }
        set { scheduleKindRawValue = newValue.rawValue }
    }

    var resolvedPaymentStartDay: Int {
        paymentStartDay ?? dueDay
    }

    var resolvedHasExplicitDueDate: Bool {
        guard hasExplicitDueDate == true else { return false }
        if scheduleKind == .recurring {
            return dueDay != resolvedPaymentStartDay
        }
        guard let dueDate, let paymentStartDate else { return false }
        let dueDay = MistiaCalendar.current.startOfDay(for: dueDate)
        let paymentDay = MistiaCalendar.current.startOfDay(for: paymentStartDate)
        return dueDay != paymentDay && dueDay >= paymentDay
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
        name: String,
        iconSymbolName: String,
        amountPerCycleMinor: Int64,
        dueDay: Int,
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
        sourceKind: PlanningDueSourceKind,
        sourceID: UUID,
        selectedMonthKey: String,
        scheduledDate: Date,
        amountMinorSnapshot: Int64? = nil,
        status: PlanningDueOccurrenceStatus = .pending,
        paidAt: Date? = nil,
        linkedTransactionID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        remoteVersion: Int64 = 0
    ) {
        self.id = id
        self.sourceKindRawValue = sourceKind.rawValue
        self.sourceID = sourceID
        self.selectedMonthKey = selectedMonthKey
        self.scheduledDate = scheduledDate
        self.amountMinorSnapshot = amountMinorSnapshot
        self.statusRawValue = status.rawValue
        self.paidAt = paidAt
        self.linkedTransactionID = linkedTransactionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
    }

    var sourceKind: PlanningDueSourceKind {
        get { PlanningDueSourceKind(rawValue: sourceKindRawValue) ?? .creditCard }
        set { sourceKindRawValue = newValue.rawValue }
    }

    var status: PlanningDueOccurrenceStatus {
        get { PlanningDueOccurrenceStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }
}
