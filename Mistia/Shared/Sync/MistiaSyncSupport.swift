import Foundation
import SwiftData

enum MistiaInitialSyncChoice: String, CaseIterable, Identifiable {
    case mergeSafely
    case useDevice
    case useCloud

    var id: String { rawValue }
}

enum MistiaInitialSyncMode: Equatable {
    case idle
    case uploadLocal
    case downloadCloud
    case choose
}

struct MistiaInitialSyncPreview: Identifiable, Equatable {
    let id = UUID()
    let mode: MistiaInitialSyncMode
    let localActiveCount: Int
    let remoteActiveCount: Int

    var requiresChoice: Bool {
        mode == .choose
    }
}

enum MistiaSyncConflictKind: String, Codable, CaseIterable, Sendable {
    case createCreate
    case editEdit
    case editDelete
    case deleteEdit
}

enum MistiaSyncConflictResolution {
    case useLocal
    case useRemote
}

struct MistiaSyncConflictDifference: Identifiable, Equatable {
    let id: String
    let fieldTitle: String
    let localValue: String
    let remoteValue: String
    let localRawValue: String?
    let remoteRawValue: String?
}

struct MistiaSyncConflictRecordSummary: Equatable {
    let title: String
    let detail: String
}

enum MistiaSyncPossibleDuplicateReason: String, Identifiable {
    case sameDaySameAmountSameWallet
    case sameDaySameAmountSameWalletSimilarText

    var id: String { rawValue }
}

struct MistiaSyncPossibleDuplicate: Identifiable, Equatable {
    let id: String
    let firstTransactionID: UUID
    let secondTransactionID: UUID
    let reason: MistiaSyncPossibleDuplicateReason
}

nonisolated enum MistiaSyncDeviceIdentity {
    nonisolated private static let defaultsKey = "mistia.sync.device-id"

    nonisolated static func current(defaults: UserDefaults = .standard) -> UUID {
        if let rawValue = defaults.string(forKey: defaultsKey),
           let existing = UUID(uuidString: rawValue) {
            return existing
        }

        let newValue = UUID()
        defaults.set(newValue.uuidString.lowercased(), forKey: defaultsKey)
        return newValue
    }
}

nonisolated protocol MistiaSyncLocalRecord: AnyObject, PersistentModel {
    static var syncEntity: MistiaSyncEntity { get }

    var id: UUID { get }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var remoteVersion: Int64 { get set }
}

nonisolated extension MistiaSyncLocalRecord {
    var isDeletedForSync: Bool {
        deletedAt != nil
    }

    func markDeleted(at date: Date) {
        deletedAt = date
        updatedAt = date
    }

    func restoreFromDelete(at date: Date) {
        deletedAt = nil
        updatedAt = date
    }
}

nonisolated extension LedgerWallet: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .wallet
}

nonisolated extension CreditCardProfile: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .creditCardProfile
}

nonisolated extension TransactionCategory: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .category
}

nonisolated extension LedgerTransaction: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .transaction
}

nonisolated extension SettlementGroup: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .settlementGroup
}

nonisolated extension SettlementParticipant: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .settlementParticipant
}

nonisolated extension BudgetPlan: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .budgetPlan
}

nonisolated extension SavingsGoal: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .savingsGoal
}

nonisolated extension RecurringBillPlan: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .recurringBillPlan
}

nonisolated extension InstallmentPlan: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .installmentPlan
}

nonisolated extension DueOccurrenceRecord: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .dueOccurrenceRecord
}

nonisolated extension InvestmentChannel: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .investmentChannel
}

nonisolated extension InvestmentAsset: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .investmentAsset
}

nonisolated extension InvestmentTrade: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .investmentTrade
}

nonisolated extension InvestmentValuation: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .investmentValuation
}

nonisolated extension InvestmentWalletPosting: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .investmentPosting
}

nonisolated extension SyncConflict {
    var entity: MistiaSyncEntity {
        MistiaSyncEntity(rawValue: entityRawValue) ?? .transaction
    }

    var conflictKind: MistiaSyncConflictKind {
        MistiaSyncConflictKind(rawValue: conflictKindRawValue) ?? .editEdit
    }

    var localPreviewTitle: String {
        (try? MistiaSyncUploadRecord.decode(
            entity: entity,
            jsonString: localPayloadJSON
        ).previewTitle) ?? entity.displayTitle
    }

    var remotePreviewTitle: String {
        (try? MistiaSyncUploadRecord.decode(
            entity: entity,
            jsonString: remotePayloadJSON
        ).previewTitle) ?? entity.displayTitle
    }

    var localRecordSummary: MistiaSyncConflictRecordSummary {
        (try? MistiaSyncUploadRecord.decode(
            entity: entity,
            jsonString: localPayloadJSON
        ).recordSummary) ?? fallbackRecordSummary(from: localPayloadJSON)
    }

    var remoteRecordSummary: MistiaSyncConflictRecordSummary {
        (try? MistiaSyncUploadRecord.decode(
            entity: entity,
            jsonString: remotePayloadJSON
        ).recordSummary) ?? fallbackRecordSummary(from: remotePayloadJSON)
    }

    var localRecord: MistiaSyncUploadRecord? {
        try? MistiaSyncUploadRecord.decode(entity: entity, jsonString: localPayloadJSON)
    }

    var remoteRecord: MistiaSyncUploadRecord? {
        try? MistiaSyncUploadRecord.decode(entity: entity, jsonString: remotePayloadJSON)
    }

    var localUpdatedAt: Date? {
        localRecord?.updatedAt
    }

    var remoteUpdatedAt: Date? {
        remoteRecord?.updatedAt
    }

    var isRemoteNewer: Bool {
        guard let r = remoteUpdatedAt, let l = localUpdatedAt else { return false }
        return r > l
    }

    var conflictDifferences: [MistiaSyncConflictDifference] {
        guard
            let localRecord = try? MistiaSyncUploadRecord.decode(entity: entity, jsonString: localPayloadJSON),
            let remoteRecord = try? MistiaSyncUploadRecord.decode(entity: entity, jsonString: remotePayloadJSON)
        else {
            return rawPayloadDifferences(
                localJSON: localPayloadJSON,
                remoteJSON: remotePayloadJSON
            )
        }
        let semanticDifferences = localRecord.conflictDifferences(comparedWith: remoteRecord)
        let metadataDifferences = localRecord.syncMetadataDifferences(comparedWith: remoteRecord)
        return semanticDifferences.isEmpty
            ? metadataDifferences
            : semanticDifferences + metadataDifferences
    }

    private func fallbackRecordSummary(from json: String) -> MistiaSyncConflictRecordSummary {
        let fields = rawPayloadFields(json)
        let title = firstNonEmpty(
            fields["title"],
            fields["name"],
            fields["issuer_name"],
            fields["last4"],
            fields["selected_month_key"]
        ) ?? entity.displayTitle
        let detail = [
            fields["amount_minor"],
            fields["currency_code"],
            fields["updated_at"].map { "updated \($0)" },
            fields["sync_version"].map { "v\($0)" },
            fields["deleted_at"].map { "deleted \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
        return MistiaSyncConflictRecordSummary(title: title, detail: detail)
    }
}

nonisolated private extension MistiaSyncUploadRecord {
    var recordSummary: MistiaSyncConflictRecordSummary {
        switch self {
        case .wallet(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.name,
                detail: compactJoined(
                    row.kindRawValue,
                    row.currencyCode,
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .creditCardProfile(let row):
            let title = row.issuerName.isEmpty ? row.last4 : "\(row.issuerName) \(row.last4)"
            return MistiaSyncConflictRecordSummary(
                title: title,
                detail: compactJoined(
                    row.networkRawValue,
                    currency(row.creditLimitMinor, code: "JPY"),
                    L10n.shared.sync.mistiasync.closesValueDueValue(String(describing: row.statementClosingDay), String(describing: row.paymentDueDay)),
                    deleted(row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .category(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.name,
                detail: compactJoined(
                    row.kindRawValue,
                    row.systemKey,
                    row.isFavorite ? L10n.shared.sync.mistiasync.favorite : nil,
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .transaction(let row):
            let title = row.title.isEmpty
                ? L10n.shared.sync.mistiasync.unnamedTransaction2
                : row.title
            return MistiaSyncConflictRecordSummary(
                title: compactJoined(title, formattedPlainAmount(row.amountMinor)),
                detail: compactJoined(
                    row.primaryKindRawValue,
                    date(row.occurredAt),
                    row.entryStatusRawValue,
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .settlementGroup(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.title,
                detail: compactJoined(
                    row.kindRawValue,
                    row.statusRawValue,
                    currency(row.expectedMinor, code: row.currencyCode),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .settlementParticipant(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.displayName,
                detail: compactJoined(
                    uuid(row.groupID),
                    row.isSelf ? "self" : nil,
                    String(row.sortOrder),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .budgetPlan(let row):
            return MistiaSyncConflictRecordSummary(
                title: compactJoined(L10n.shared.sync.mistiasync.budget2, currency(row.limitMinor, code: row.currencyCode)),
                detail: compactJoined(
                    date(row.monthAnchor),
                    uuid(row.categoryID),
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .savingsGoal(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.name,
                detail: compactJoined(
                    currency(row.currentSavedMinor, code: row.currencyCode),
                    L10n.shared.sync.mistiasync.targetValue(String(describing: currency(row.targetMinor, code: row.currencyCode))),
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .recurringBillPlan(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.name,
                detail: compactJoined(
                    row.amountMinor.map { currency($0, code: row.currencyCode) },
                    L10n.shared.sync.mistiasync.dayValue(String(describing: row.dueDay)),
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .installmentPlan(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.name,
                detail: compactJoined(
                    currency(row.amountPerCycleMinor, code: row.currencyCode),
                    row.totalCycles.map { L10n.shared.sync.mistiasync.valueCycles(String(describing: $0)) },
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .dueOccurrence(let row):
            return MistiaSyncConflictRecordSummary(
                title: compactJoined(L10n.shared.sync.mistiasync.dueOccurrence2, row.selectedMonthKey),
                detail: compactJoined(
                    row.sourceKindRawValue,
                    date(row.scheduledDate),
                    row.amountMinorSnapshot.map(number),
                    row.statusRawValue,
                    deleted(row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .investmentChannel(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.name,
                detail: compactJoined(
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .investmentAsset(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.name,
                detail: compactJoined(
                    row.currencyCode,
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .investmentTrade(let row):
            return MistiaSyncConflictRecordSummary(
                title: row.kindRawValue == InvestmentTradeKind.buy.rawValue
                    ? L10n.investment.hub.buy
                    : L10n.investment.hub.sell,
                detail: compactJoined(
                    row.quantityDecimalString,
                    currency(row.grossAmountMinor, code: row.currencyCode),
                    date(row.occurredAt),
                    deleted(row.deletedAt),
                    version(row.syncVersion)
                )
            )
        case .investmentValuation(let row):
            return MistiaSyncConflictRecordSummary(
                title: L10n.investment.valuation.title,
                detail: compactJoined(
                    currency(row.marketValueMinor, code: row.currencyCode),
                    date(row.valuedAt),
                    deleted(row.deletedAt),
                    version(row.syncVersion)
                )
            )
        case .investmentPosting(let row):
            return MistiaSyncConflictRecordSummary(
                title: L10n.investment.wallet.detailTitle,
                detail: compactJoined(
                    row.roleRawValue,
                    currency(row.amountMinor, code: row.currencyCode),
                    date(row.occurredAt),
                    deleted(row.deletedAt),
                    version(row.syncVersion)
                )
            )
        }
    }

    func conflictDifferences(comparedWith remote: MistiaSyncUploadRecord) -> [MistiaSyncConflictDifference] {
        guard entity == remote.entity else { return [] }

        switch (self, remote) {
        case (.wallet(let local), .wallet(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("name", L10n.shared.sync.mistiasync.name, local.name, remote.name)
                field("kind", L10n.shared.sync.mistiasync.walletType, local.kindRawValue, remote.kindRawValue)
                field("icon", L10n.shared.sync.mistiasync.icon, local.iconSymbolName, remote.iconSymbolName)
                field("color", L10n.shared.sync.mistiasync.color, local.iconColorHex, remote.iconColorHex)
                field("currency", L10n.shared.sync.mistiasync.currency, local.currencyCode, remote.currencyCode)
                field("opening", L10n.shared.sync.mistiasync.openingBalance, currency(local.openingBalanceMinor, code: local.currencyCode), currency(remote.openingBalanceMinor, code: remote.currencyCode))
                field("institution", L10n.shared.sync.mistiasync.institution, local.institutionDisplayName, remote.institutionDisplayName)
                field("preset", L10n.shared.sync.mistiasync.institutionPreset, local.institutionPresetKey, remote.institutionPresetKey)
                field("sort", L10n.shared.sync.mistiasync.sortOrder, number(local.sortOrder), number(remote.sortOrder))
                field("archived", L10n.shared.sync.mistiasync.archived2, yesNo(local.isArchived), yesNo(remote.isArchived))
                field("archivedAt", L10n.shared.sync.mistiasync.archivedAt, date(local.archivedAt), date(remote.archivedAt))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.creditCardProfile(let local), .creditCardProfile(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("issuer", L10n.shared.sync.mistiasync.cardName, local.issuerName, remote.issuerName)
                field("network", L10n.shared.sync.mistiasync.cardNetwork, local.networkRawValue, remote.networkRawValue)
                field("last4", L10n.shared.sync.mistiasync.lastDigits, local.last4, remote.last4)
                field("limit", L10n.shared.sync.mistiasync.creditLimit, currency(local.creditLimitMinor, code: "JPY"), currency(remote.creditLimitMinor, code: "JPY"))
                field("closing", L10n.shared.sync.mistiasync.closingDay, number(local.statementClosingDay), number(remote.statementClosingDay))
                field("due", L10n.shared.sync.mistiasync.dueDay, number(local.paymentDueDay), number(remote.paymentDueDay))
                field("notes", L10n.shared.sync.mistiasync.notes, local.notes, remote.notes)
                field("wallet", L10n.shared.sync.mistiasync.cardWallet, uuid(local.walletID), uuid(remote.walletID))
                field("sourceWallet", L10n.shared.sync.mistiasync.paymentWallet, uuid(local.paymentSourceWalletID), uuid(remote.paymentSourceWalletID))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.category(let local), .category(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("name", L10n.shared.sync.mistiasync.name, local.name, remote.name)
                field("nameEnglish", L10n.shared.sync.mistiasync.englishName, local.nameEnglish, remote.nameEnglish)
                field("nameJapanese", L10n.shared.sync.mistiasync.japaneseName, local.nameJapanese, remote.nameJapanese)
                field("kind", L10n.shared.sync.mistiasync.kind, local.kindRawValue, remote.kindRawValue)
                field("icon", L10n.shared.sync.mistiasync.icon, local.iconSymbolName, remote.iconSymbolName)
                field("color", L10n.shared.sync.mistiasync.color, local.iconColorHex, remote.iconColorHex)
                field("favorite", L10n.shared.sync.mistiasync.favorite, yesNo(local.isFavorite), yesNo(remote.isFavorite))
                field("familyBudget", L10n.shared.sync.mistiasync.familyBudget, yesNo(local.familyBudgetSpendingEnabled), yesNo(remote.familyBudgetSpendingEnabled))
                field("parent", L10n.shared.sync.mistiasync.parentCategory, uuid(local.parentCategoryID), uuid(remote.parentCategoryID))
                field("role", L10n.shared.sync.mistiasync.hierarchyRole, local.hierarchyRoleRawValue, remote.hierarchyRoleRawValue)
                field("systemKey", L10n.shared.sync.mistiasync.systemKey, local.systemKey, remote.systemKey)
                field("system", L10n.shared.sync.mistiasync.systemCategory, yesNo(local.isSystem), yesNo(remote.isSystem))
                field("sort", L10n.shared.sync.mistiasync.sortOrder, number(local.sortOrder), number(remote.sortOrder))
                field("archived", L10n.shared.sync.mistiasync.archived2, yesNo(local.isArchived), yesNo(remote.isArchived))
                field("archivedAt", L10n.shared.sync.mistiasync.archivedAt, date(local.archivedAt), date(remote.archivedAt))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.transaction(let local), .transaction(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("kind", L10n.shared.sync.mistiasync.transactionType, local.primaryKindRawValue, remote.primaryKindRawValue)
                field("transfer", L10n.shared.sync.mistiasync.transferSubtype, local.transferSubtypeRawValue, remote.transferSubtypeRawValue)
                field("debt", L10n.shared.sync.mistiasync.debtIntent, local.debtIntentRawValue, remote.debtIntentRawValue)
                field("status", L10n.shared.sync.mistiasync.status, local.entryStatusRawValue, remote.entryStatusRawValue)
                field("title", L10n.shared.sync.mistiasync.title, local.title, remote.title)
                field("note", L10n.shared.sync.mistiasync.note, local.note, remote.note)
                field("amount", L10n.shared.sync.mistiasync.amount, number(local.amountMinor), number(remote.amountMinor))
                field("occurred", L10n.shared.sync.mistiasync.transactionDate, date(local.occurredAt), date(remote.occurredAt))
                field("counterparty", L10n.shared.sync.mistiasync.counterparty, local.counterpartyName, remote.counterpartyName)
                field("sourceWallet", L10n.shared.sync.mistiasync.sourceWallet, uuid(local.sourceWalletID), uuid(remote.sourceWalletID))
                field("destinationWallet", L10n.shared.sync.mistiasync.destinationWallet, uuid(local.destinationWalletID), uuid(remote.destinationWalletID))
                field("category", L10n.shared.sync.mistiasync.category2, uuid(local.categoryID), uuid(remote.categoryID))
                field("archived", L10n.shared.sync.mistiasync.archived2, yesNo(local.isArchived), yesNo(remote.isArchived))
                field("archivedAt", L10n.shared.sync.mistiasync.archivedAt, date(local.archivedAt), date(remote.archivedAt))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.settlementGroup(let local), .settlementGroup(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("title", L10n.shared.sync.mistiasync.title, local.title, remote.title)
                field("kind", L10n.shared.sync.mistiasync.kind, local.kindRawValue, remote.kindRawValue)
                field("status", L10n.shared.sync.mistiasync.status, local.statusRawValue, remote.statusRawValue)
                field("currency", L10n.shared.sync.mistiasync.currency, local.currencyCode, remote.currencyCode)
                field("occurred", L10n.shared.sync.mistiasync.transactionDate, date(local.occurredAt), date(remote.occurredAt))
                field("total", L10n.shared.sync.mistiasync.amount, currency(local.totalMinor, code: local.currencyCode), currency(remote.totalMinor, code: remote.currencyCode))
                field("expected", L10n.shared.sync.mistiasync.amount, currency(local.expectedMinor, code: local.currencyCode), currency(remote.expectedMinor, code: remote.currencyCode))
                field("settled", L10n.shared.sync.mistiasync.saved, currency(local.settledMinor, code: local.currencyCode), currency(remote.settledMinor, code: remote.currencyCode))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.settlementParticipant(let local), .settlementParticipant(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("group", L10n.shared.sync.mistiasync.kind, uuid(local.groupID), uuid(remote.groupID))
                field("displayName", L10n.shared.sync.mistiasync.title, local.displayName, remote.displayName)
                field("normalizedKey", L10n.shared.sync.mistiasync.counterparty, local.normalizedKey, remote.normalizedKey)
                field("member", L10n.shared.sync.mistiasync.sourceWallet, uuid(local.memberUserID), uuid(remote.memberUserID))
                field("self", L10n.shared.sync.mistiasync.status, yesNo(local.isSelf), yesNo(remote.isSelf))
                field("sortOrder", L10n.shared.sync.mistiasync.kind, String(local.sortOrder), String(remote.sortOrder))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.budgetPlan(let local), .budgetPlan(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("category", L10n.shared.sync.mistiasync.category2, uuid(local.categoryID), uuid(remote.categoryID))
                field("categorySnapshot", L10n.shared.sync.mistiasync.categorySnapshot, local.categoryNameSnapshot, remote.categoryNameSnapshot)
                field("parentSnapshot", L10n.shared.sync.mistiasync.parentSnapshot, local.categoryParentNameSnapshot, remote.categoryParentNameSnapshot)
                field("familyBudget", L10n.shared.sync.mistiasync.familyBudget, yesNo(local.includesFamilySpending), yesNo(remote.includesFamilySpending))
                field("month", L10n.shared.sync.mistiasync.month, date(local.monthAnchor), date(remote.monthAnchor))
                field("limit", L10n.shared.sync.mistiasync.limit, currency(local.limitMinor, code: local.currencyCode), currency(remote.limitMinor, code: remote.currencyCode))
                field("rollover", L10n.shared.sync.mistiasync.rollover, yesNo(local.rolloverEnabled), yesNo(remote.rolloverEnabled))
                field("currency", L10n.shared.sync.mistiasync.currency, local.currencyCode, remote.currencyCode)
                field("archived", L10n.shared.sync.mistiasync.archived2, yesNo(local.isArchived), yesNo(remote.isArchived))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.savingsGoal(let local), .savingsGoal(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("name", L10n.shared.sync.mistiasync.name, local.name, remote.name)
                field("icon", L10n.shared.sync.mistiasync.icon, local.iconSymbolName, remote.iconSymbolName)
                field("target", L10n.shared.sync.mistiasync.target, currency(local.targetMinor, code: local.currencyCode), currency(remote.targetMinor, code: remote.currencyCode))
                field("saved", L10n.shared.sync.mistiasync.saved, currency(local.currentSavedMinor, code: local.currencyCode), currency(remote.currentSavedMinor, code: remote.currencyCode))
                field("targetDate", L10n.shared.sync.mistiasync.targetDate, date(local.targetDate), date(remote.targetDate))
                field("wallet", L10n.shared.sync.mistiasync.linkedWallet, uuid(local.linkedWalletID), uuid(remote.linkedWalletID))
                field("currency", L10n.shared.sync.mistiasync.currency, local.currencyCode, remote.currencyCode)
                field("sort", L10n.shared.sync.mistiasync.sortOrder, number(local.sortOrder), number(remote.sortOrder))
                field("archived", L10n.shared.sync.mistiasync.archived2, yesNo(local.isArchived), yesNo(remote.isArchived))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.recurringBillPlan(let local), .recurringBillPlan(let remote)):
            return recurringPlanDifferences(
                localName: local.name,
                remoteName: remote.name,
                localIcon: local.iconSymbolName,
                remoteIcon: remote.iconSymbolName,
                localCategoryID: local.categoryID,
                remoteCategoryID: remote.categoryID,
                localAmount: local.amountMinor,
                remoteAmount: remote.amountMinor,
                localDueDay: local.dueDay,
                remoteDueDay: remote.dueDay,
                localFrequency: local.frequencyMonths,
                remoteFrequency: remote.frequencyMonths,
                localPaymentWalletID: local.paymentWalletID,
                remotePaymentWalletID: remote.paymentWalletID,
                localCurrencyCode: local.currencyCode,
                remoteCurrencyCode: remote.currencyCode,
                localArchived: local.isArchived,
                remoteArchived: remote.isArchived,
                localPaused: local.isPaused,
                remotePaused: remote.isPaused,
                localPausedAt: local.pausedAt,
                remotePausedAt: remote.pausedAt,
                localResumeStartMonth: local.resumeStartMonth,
                remoteResumeStartMonth: remote.resumeStartMonth,
                localDeletedAt: local.deletedAt,
                remoteDeletedAt: remote.deletedAt
            )
        case (.installmentPlan(let local), .installmentPlan(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("name", L10n.shared.sync.mistiasync.name, local.name, remote.name)
                field("icon", L10n.shared.sync.mistiasync.icon, local.iconSymbolName, remote.iconSymbolName)
                field("amount", L10n.shared.sync.mistiasync.amountPerCycle, currency(local.amountPerCycleMinor, code: local.currencyCode), currency(remote.amountPerCycleMinor, code: remote.currencyCode))
                field("dueDay", L10n.shared.sync.mistiasync.dueDay, number(local.dueDay), number(remote.dueDay))
                field("cycles", L10n.shared.sync.mistiasync.cycles, local.totalCycles.map(number), remote.totalCycles.map(number))
                field("frequency", L10n.shared.sync.mistiasync.monthlyFrequency, number(local.frequencyMonths), number(remote.frequencyMonths))
                field("wallet", L10n.shared.sync.mistiasync.paymentWallet, uuid(local.paymentWalletID), uuid(remote.paymentWalletID))
                field("currency", L10n.shared.sync.mistiasync.currency, local.currencyCode, remote.currencyCode)
                field("archived", L10n.shared.sync.mistiasync.archived2, yesNo(local.isArchived), yesNo(remote.isArchived))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.dueOccurrence(let local), .dueOccurrence(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("sourceKind", L10n.shared.sync.mistiasync.source, local.sourceKindRawValue, remote.sourceKindRawValue)
                field("source", L10n.shared.sync.mistiasync.source, uuid(local.sourceID), uuid(remote.sourceID))
                field("month", L10n.shared.sync.mistiasync.month, local.selectedMonthKey, remote.selectedMonthKey)
                field("scheduled", L10n.shared.sync.mistiasync.scheduledDate, date(local.scheduledDate), date(remote.scheduledDate))
                field("amount", L10n.shared.sync.mistiasync.amount, local.amountMinorSnapshot.map(number), remote.amountMinorSnapshot.map(number))
                field("status", L10n.shared.sync.mistiasync.status, local.statusRawValue, remote.statusRawValue)
                field("paidAt", L10n.shared.sync.mistiasync.paidAt, date(local.paidAt), date(remote.paidAt))
                field("transaction", L10n.shared.sync.mistiasync.linkedTransaction, uuid(local.linkedTransactionID), uuid(remote.linkedTransactionID))
                field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        default:
            return []
        }
    }

    func syncMetadataDifferences(comparedWith remote: MistiaSyncUploadRecord) -> [MistiaSyncConflictDifference] {
        MistiaSyncConflictDifferenceBuilder.build {
            field("updatedAt", L10n.shared.sync.mistiasync.updatedAt, date(updatedAt), date(remote.updatedAt))
            field("version", L10n.shared.sync.mistiasync.syncVersion, number(syncVersion), number(remote.syncVersion))
            field("device", L10n.shared.sync.mistiasync.lastModifiedDevice, uuid(lastModifiedByDeviceID), uuid(remote.lastModifiedByDeviceID))
            field("deletedAt", L10n.shared.sync.mistiasync.deletedAt, date(deletedAt), date(remote.deletedAt))
        }
    }

    private func recurringPlanDifferences(
        localName: String,
        remoteName: String,
        localIcon: String,
        remoteIcon: String,
        localCategoryID: UUID?,
        remoteCategoryID: UUID?,
        localAmount: Int64?,
        remoteAmount: Int64?,
        localDueDay: Int,
        remoteDueDay: Int,
        localFrequency: Int,
        remoteFrequency: Int,
        localPaymentWalletID: UUID?,
        remotePaymentWalletID: UUID?,
        localCurrencyCode: String,
        remoteCurrencyCode: String,
        localArchived: Bool,
        remoteArchived: Bool,
        localPaused: Bool,
        remotePaused: Bool,
        localPausedAt: Date?,
        remotePausedAt: Date?,
        localResumeStartMonth: Date?,
        remoteResumeStartMonth: Date?,
        localDeletedAt: Date?,
        remoteDeletedAt: Date?
    ) -> [MistiaSyncConflictDifference] {
        MistiaSyncConflictDifferenceBuilder.build {
            field("name", L10n.shared.sync.mistiasync.name, localName, remoteName)
            field("icon", L10n.shared.sync.mistiasync.icon, localIcon, remoteIcon)
            field("category", L10n.shared.sync.mistiasync.category2, uuid(localCategoryID), uuid(remoteCategoryID))
            field("amount", L10n.shared.sync.mistiasync.amount, localAmount.map { currency($0, code: localCurrencyCode) }, remoteAmount.map { currency($0, code: remoteCurrencyCode) })
            field("dueDay", L10n.shared.sync.mistiasync.dueDay, number(localDueDay), number(remoteDueDay))
            field("frequency", L10n.shared.sync.mistiasync.monthlyFrequency, number(localFrequency), number(remoteFrequency))
            field("wallet", L10n.shared.sync.mistiasync.paymentWallet, uuid(localPaymentWalletID), uuid(remotePaymentWalletID))
            field("currency", L10n.shared.sync.mistiasync.currency, localCurrencyCode, remoteCurrencyCode)
            field("archived", L10n.shared.sync.mistiasync.archived2, yesNo(localArchived), yesNo(remoteArchived))
            field("paused", L10n.shared.sync.mistiasync.paused, yesNo(localPaused), yesNo(remotePaused))
            field("pausedAt", L10n.shared.sync.mistiasync.pausedAt, date(localPausedAt), date(remotePausedAt))
            field("resumeStartMonth", L10n.shared.sync.mistiasync.resumeStartMonth, date(localResumeStartMonth), date(remoteResumeStartMonth))
            field("deleted", L10n.shared.sync.mistiasync.deleteStatus, deleted(localDeletedAt), deleted(remoteDeletedAt))
        }
    }
}

nonisolated private enum MistiaSyncConflictDifferenceBuilder {
    static func build(
        @MistiaSyncConflictDifferenceListBuilder _ body: () -> [MistiaSyncConflictDifference]
    ) -> [MistiaSyncConflictDifference] {
        body()
    }
}

@resultBuilder
nonisolated private enum MistiaSyncConflictDifferenceListBuilder {
    static func buildBlock(_ components: [MistiaSyncConflictDifference]...) -> [MistiaSyncConflictDifference] {
        components.flatMap { $0 }
    }
}

nonisolated private func field(
    _ id: String,
    _ title: String,
    _ localValue: String?,
    _ remoteValue: String?
) -> [MistiaSyncConflictDifference] {
    let local = displayValue(localValue)
    let remote = displayValue(remoteValue)
    guard local != remote else { return [] }
    return [
        MistiaSyncConflictDifference(
            id: id,
            fieldTitle: title,
            localValue: local,
            remoteValue: remote,
            localRawValue: localValue,
            remoteRawValue: remoteValue
        )
    ]
}

nonisolated private func displayValue(_ value: String?) -> String {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return L10n.shared.sync.mistiasync.none
    }
    if UUID(uuidString: value) != nil {
        return L10n.shared.sync.mistiasync.nameUnavailable
    }
    return value
}

nonisolated private func firstNonEmpty(_ values: String?...) -> String? {
    values.first { value in
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } ?? nil
}

nonisolated private func compactJoined(_ values: String?...) -> String {
    values
        .compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: " • ")
}

nonisolated private func number(_ value: Int) -> String {
    "\(value)"
}

nonisolated private func number(_ value: Int64) -> String {
    "\(value)"
}

nonisolated private func currency(_ amountMinor: Int64, code: String) -> String {
    amountMinor.formattedCurrency(code: code)
}

nonisolated private func formattedPlainAmount(_ amount: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
}

nonisolated private func date(_ value: Date?) -> String? {
    value.map { MistiaDateFormatting.dateTimeString(for: $0) }
}

nonisolated private func uuid(_ value: UUID?) -> String? {
    value.map { String($0.uuidString.lowercased().prefix(8)) }
}

nonisolated private func yesNo(_ value: Bool) -> String {
    value
        ? L10n.shared.sync.mistiasync.yes
        : L10n.shared.sync.mistiasync.no
}

nonisolated private func deleted(_ value: Date?) -> String {
    if let value {
        return L10n.shared.sync.mistiasync.deletedAtValue(String(describing: MistiaDateFormatting.dateTimeString(for: value)))
    }
    return L10n.shared.sync.mistiasync.active2
}

nonisolated private func recordState(isArchived: Bool, deletedAt: Date?) -> String {
    if deletedAt != nil {
        return L10n.shared.sync.mistiasync.deleted
    }
    if isArchived {
        return L10n.shared.sync.mistiasync.archived
    }
    return L10n.shared.sync.mistiasync.active
}

nonisolated private func version(_ value: Int64) -> String {
    "v\(value)"
}

nonisolated private func rawPayloadDifferences(
    localJSON: String,
    remoteJSON: String
) -> [MistiaSyncConflictDifference] {
    let localFields = rawPayloadFields(localJSON)
    let remoteFields = rawPayloadFields(remoteJSON)
    let keys = Set(localFields.keys).union(remoteFields.keys).sorted()
    return keys.compactMap { key in
        let local = displayValue(localFields[key])
        let remote = displayValue(remoteFields[key])
        guard local != remote else { return nil }
        return MistiaSyncConflictDifference(
            id: key,
            fieldTitle: readableFieldName(key),
            localValue: local,
            remoteValue: remote,
            localRawValue: localFields[key],
            remoteRawValue: remoteFields[key]
        )
    }
}

nonisolated private func rawPayloadFields(_ json: String) -> [String: String] {
    guard
        let data = json.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return [:]
    }

    return object.reduce(into: [String: String]()) { result, pair in
        guard !(pair.value is NSNull) else { return }
        if let value = pair.value as? String {
            result[pair.key] = value
        } else if let value = pair.value as? Bool {
            result[pair.key] = yesNo(value)
        } else if let value = pair.value as? NSNumber {
            result[pair.key] = value.stringValue
        } else {
            result[pair.key] = "\(pair.value)"
        }
    }
}

nonisolated private func readableFieldName(_ key: String) -> String {
    switch key.lowercased() {
    case "wallet_id":
        return L10n.shared.sync.mistiasync.wallet2
    case "source_wallet_id":
        return L10n.shared.sync.mistiasync.sourceWallet
    case "destination_wallet_id":
        return L10n.shared.sync.mistiasync.destinationWallet
    case "payment_wallet_id":
        return L10n.shared.sync.mistiasync.paymentWallet
    case "linked_wallet_id":
        return L10n.shared.sync.mistiasync.linkedWallet
    case "category_id":
        return L10n.shared.sync.mistiasync.category2
    case "parent_category_id":
        return L10n.shared.sync.mistiasync.parentCategory
    case "transaction_id", "linked_transaction_id":
        return L10n.shared.sync.mistiasync.transaction2
    case "source_id":
        return L10n.shared.sync.mistiasync.source
    default:
        break
    }

    return key
        .split(separator: "_")
        .filter { $0.lowercased() != "id" && $0.lowercased() != "uid" }
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}
