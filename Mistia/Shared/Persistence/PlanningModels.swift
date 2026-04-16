import Foundation
import SwiftData

@Model
final class BudgetPlan {
    @Attribute(.unique) var id: UUID
    @Relationship(deleteRule: .nullify) var category: TransactionCategory?
    var monthAnchor: Date
    var limitMinor: Int64
    var rolloverEnabled: Bool
    var currencyCode: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var remoteVersion: Int64 = 0

    init(
        id: UUID = UUID(),
        category: TransactionCategory? = nil,
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
    var remoteVersion: Int64 = 0

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
    var frequencyMonths: Int
    @Relationship(deleteRule: .nullify) var paymentWallet: LedgerWallet?
    var currencyCode: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var remoteVersion: Int64 = 0

    init(
        id: UUID = UUID(),
        name: String,
        iconSymbolName: String,
        category: TransactionCategory? = nil,
        amountMinor: Int64? = nil,
        dueDay: Int,
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
    var remoteVersion: Int64 = 0

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
    var remoteVersion: Int64 = 0

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
