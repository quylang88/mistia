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

enum MistiaSyncConflictKind: String, Codable, CaseIterable {
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

enum MistiaSyncDeviceIdentity {
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

protocol MistiaSyncLocalRecord: AnyObject, PersistentModel {
    static var syncEntity: MistiaSyncEntity { get }

    var id: UUID { get }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var remoteVersion: Int64 { get set }
}

extension MistiaSyncLocalRecord {
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

extension LedgerWallet: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .wallet
}

extension CreditCardProfile: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .creditCardProfile
}

extension TransactionCategory: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .category
}

extension LedgerTransaction: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .transaction
}

extension BudgetPlan: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .budgetPlan
}

extension SavingsGoal: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .savingsGoal
}

extension RecurringBillPlan: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .recurringBillPlan
}

extension InstallmentPlan: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .installmentPlan
}

extension DueOccurrenceRecord: MistiaSyncLocalRecord {
    static let syncEntity: MistiaSyncEntity = .dueOccurrenceRecord
}

extension SyncConflict {
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

private extension MistiaSyncUploadRecord {
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
                    mistiaLocalized(vi: "Chốt \(row.statementClosingDay), hạn \(row.paymentDueDay)", en: "Closes \(row.statementClosingDay), due \(row.paymentDueDay)", ja: "締め \(row.statementClosingDay), 支払 \(row.paymentDueDay)"),
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
                    row.isFavorite ? mistiaLocalized(vi: "Yêu thích", en: "Favorite", ja: "お気に入り") : nil,
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .transaction(let row):
            let title = row.title.isEmpty
                ? mistiaLocalized(vi: "Giao dịch không tên", en: "Unnamed transaction", ja: "無名取引")
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
        case .budgetPlan(let row):
            return MistiaSyncConflictRecordSummary(
                title: compactJoined(mistiaLocalized(vi: "Ngân sách", en: "Budget", ja: "予算"), currency(row.limitMinor, code: row.currencyCode)),
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
                    mistiaLocalized(vi: "Mục tiêu \(currency(row.targetMinor, code: row.currencyCode))", en: "Target \(currency(row.targetMinor, code: row.currencyCode))", ja: "目標 \(currency(row.targetMinor, code: row.currencyCode))"),
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
                    mistiaLocalized(vi: "Ngày \(row.dueDay)", en: "Day \(row.dueDay)", ja: "\(row.dueDay)日"),
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
                    row.totalCycles.map { mistiaLocalized(vi: "\($0) kỳ", en: "\($0) cycles", ja: "\($0)回") },
                    recordState(isArchived: row.isArchived, deletedAt: row.deletedAt),
                    version(row.syncVersion),
                    date(row.updatedAt)
                )
            )
        case .dueOccurrence(let row):
            return MistiaSyncConflictRecordSummary(
                title: compactJoined(mistiaLocalized(vi: "Kỳ đến hạn", en: "Due occurrence", ja: "支払予定"), row.selectedMonthKey),
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
        }
    }

    func conflictDifferences(comparedWith remote: MistiaSyncUploadRecord) -> [MistiaSyncConflictDifference] {
        guard entity == remote.entity else { return [] }

        switch (self, remote) {
        case (.wallet(let local), .wallet(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("name", mistiaLocalized(vi: "Tên", en: "Name", ja: "名前"), local.name, remote.name)
                field("kind", mistiaLocalized(vi: "Loại ví", en: "Wallet type", ja: "ウォレット種別"), local.kindRawValue, remote.kindRawValue)
                field("icon", mistiaLocalized(vi: "Icon", en: "Icon", ja: "アイコン"), local.iconSymbolName, remote.iconSymbolName)
                field("color", mistiaLocalized(vi: "Màu", en: "Color", ja: "色"), local.iconColorHex, remote.iconColorHex)
                field("currency", mistiaLocalized(vi: "Tiền tệ", en: "Currency", ja: "通貨"), local.currencyCode, remote.currencyCode)
                field("opening", mistiaLocalized(vi: "Số dư đầu kỳ", en: "Opening balance", ja: "初期残高"), currency(local.openingBalanceMinor, code: local.currencyCode), currency(remote.openingBalanceMinor, code: remote.currencyCode))
                field("institution", mistiaLocalized(vi: "Ngân hàng", en: "Institution", ja: "金融機関"), local.institutionDisplayName, remote.institutionDisplayName)
                field("preset", mistiaLocalized(vi: "Preset ngân hàng", en: "Institution preset", ja: "金融機関プリセット"), local.institutionPresetKey, remote.institutionPresetKey)
                field("sort", mistiaLocalized(vi: "Thứ tự", en: "Sort order", ja: "並び順"), number(local.sortOrder), number(remote.sortOrder))
                field("archived", mistiaLocalized(vi: "Lưu trữ", en: "Archived", ja: "アーカイブ"), yesNo(local.isArchived), yesNo(remote.isArchived))
                field("archivedAt", mistiaLocalized(vi: "Lưu trữ lúc", en: "Archived at", ja: "アーカイブ日時"), date(local.archivedAt), date(remote.archivedAt))
                field("deleted", mistiaLocalized(vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態"), deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.creditCardProfile(let local), .creditCardProfile(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("issuer", mistiaLocalized(vi: "Tên thẻ", en: "Card name", ja: "カード名"), local.issuerName, remote.issuerName)
                field("network", mistiaLocalized(vi: "Mạng thẻ", en: "Card network", ja: "カードブランド"), local.networkRawValue, remote.networkRawValue)
                field("last4", mistiaLocalized(vi: "4 số cuối", en: "Last 4 digits", ja: "下4桁"), local.last4, remote.last4)
                field("limit", mistiaLocalized(vi: "Hạn mức", en: "Credit limit", ja: "利用限度額"), currency(local.creditLimitMinor, code: "JPY"), currency(remote.creditLimitMinor, code: "JPY"))
                field("closing", mistiaLocalized(vi: "Ngày chốt", en: "Closing day", ja: "締め日"), number(local.statementClosingDay), number(remote.statementClosingDay))
                field("due", mistiaLocalized(vi: "Ngày đến hạn", en: "Due day", ja: "支払日"), number(local.paymentDueDay), number(remote.paymentDueDay))
                field("notes", mistiaLocalized(vi: "Ghi chú", en: "Notes", ja: "メモ"), local.notes, remote.notes)
                field("wallet", mistiaLocalized(vi: "Ví thẻ", en: "Card wallet", ja: "カードウォレット"), uuid(local.walletID), uuid(remote.walletID))
                field("sourceWallet", mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット"), uuid(local.paymentSourceWalletID), uuid(remote.paymentSourceWalletID))
                field("deleted", mistiaLocalized(vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態"), deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.category(let local), .category(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("name", mistiaLocalized(vi: "Tên", en: "Name", ja: "名前"), local.name, remote.name)
                field("nameEnglish", mistiaLocalized(vi: "Tên tiếng Anh", en: "English name", ja: "英語名"), local.nameEnglish, remote.nameEnglish)
                field("nameJapanese", mistiaLocalized(vi: "Tên tiếng Nhật", en: "Japanese name", ja: "日本語名"), local.nameJapanese, remote.nameJapanese)
                field("kind", mistiaLocalized(vi: "Loại", en: "Kind", ja: "種別"), local.kindRawValue, remote.kindRawValue)
                field("icon", mistiaLocalized(vi: "Icon", en: "Icon", ja: "アイコン"), local.iconSymbolName, remote.iconSymbolName)
                field("color", mistiaLocalized(vi: "Màu", en: "Color", ja: "色"), local.iconColorHex, remote.iconColorHex)
                field("favorite", mistiaLocalized(vi: "Yêu thích", en: "Favorite", ja: "お気に入り"), yesNo(local.isFavorite), yesNo(remote.isFavorite))
                field("parent", mistiaLocalized(vi: "Danh mục cha", en: "Parent category", ja: "親カテゴリ"), uuid(local.parentCategoryID), uuid(remote.parentCategoryID))
                field("role", mistiaLocalized(vi: "Vai trò phân cấp", en: "Hierarchy role", ja: "階層ロール"), local.hierarchyRoleRawValue, remote.hierarchyRoleRawValue)
                field("systemKey", mistiaLocalized(vi: "Mã hệ thống", en: "System key", ja: "システムキー"), local.systemKey, remote.systemKey)
                field("system", mistiaLocalized(vi: "Danh mục hệ thống", en: "System category", ja: "システムカテゴリ"), yesNo(local.isSystem), yesNo(remote.isSystem))
                field("sort", mistiaLocalized(vi: "Thứ tự", en: "Sort order", ja: "並び順"), number(local.sortOrder), number(remote.sortOrder))
                field("archived", mistiaLocalized(vi: "Lưu trữ", en: "Archived", ja: "アーカイブ"), yesNo(local.isArchived), yesNo(remote.isArchived))
                field("archivedAt", mistiaLocalized(vi: "Lưu trữ lúc", en: "Archived at", ja: "アーカイブ日時"), date(local.archivedAt), date(remote.archivedAt))
                field("deleted", mistiaLocalized(vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態"), deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.transaction(let local), .transaction(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("kind", mistiaLocalized(vi: "Loại giao dịch", en: "Transaction type", ja: "取引種別"), local.primaryKindRawValue, remote.primaryKindRawValue)
                field("transfer", mistiaLocalized(vi: "Nhánh chuyển khoản", en: "Transfer subtype", ja: "振替サブタイプ"), local.transferSubtypeRawValue, remote.transferSubtypeRawValue)
                field("debt", mistiaLocalized(vi: "Ý định nợ", en: "Debt intent", ja: "債務区分"), local.debtIntentRawValue, remote.debtIntentRawValue)
                field("status", mistiaLocalized(vi: "Trạng thái", en: "Status", ja: "状態"), local.entryStatusRawValue, remote.entryStatusRawValue)
                field("title", mistiaLocalized(vi: "Tiêu đề", en: "Title", ja: "タイトル"), local.title, remote.title)
                field("note", mistiaLocalized(vi: "Ghi chú", en: "Note", ja: "メモ"), local.note, remote.note)
                field("amount", mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額"), number(local.amountMinor), number(remote.amountMinor))
                field("occurred", mistiaLocalized(vi: "Ngày giao dịch", en: "Transaction date", ja: "取引日"), date(local.occurredAt), date(remote.occurredAt))
                field("counterparty", mistiaLocalized(vi: "Đối tác", en: "Counterparty", ja: "相手先"), local.counterpartyName, remote.counterpartyName)
                field("sourceWallet", mistiaLocalized(vi: "Ví nguồn", en: "Source wallet", ja: "出金ウォレット"), uuid(local.sourceWalletID), uuid(remote.sourceWalletID))
                field("destinationWallet", mistiaLocalized(vi: "Ví đích", en: "Destination wallet", ja: "入金ウォレット"), uuid(local.destinationWalletID), uuid(remote.destinationWalletID))
                field("category", mistiaLocalized(vi: "Danh mục", en: "Category", ja: "カテゴリ"), uuid(local.categoryID), uuid(remote.categoryID))
                field("archived", mistiaLocalized(vi: "Lưu trữ", en: "Archived", ja: "アーカイブ"), yesNo(local.isArchived), yesNo(remote.isArchived))
                field("archivedAt", mistiaLocalized(vi: "Lưu trữ lúc", en: "Archived at", ja: "アーカイブ日時"), date(local.archivedAt), date(remote.archivedAt))
                field("deleted", mistiaLocalized(vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態"), deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.budgetPlan(let local), .budgetPlan(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("category", mistiaLocalized(vi: "Danh mục", en: "Category", ja: "カテゴリ"), uuid(local.categoryID), uuid(remote.categoryID))
                field("month", mistiaLocalized(vi: "Tháng", en: "Month", ja: "月"), date(local.monthAnchor), date(remote.monthAnchor))
                field("limit", mistiaLocalized(vi: "Hạn mức", en: "Limit", ja: "上限"), currency(local.limitMinor, code: local.currencyCode), currency(remote.limitMinor, code: remote.currencyCode))
                field("rollover", mistiaLocalized(vi: "Chuyển dư", en: "Rollover", ja: "繰り越し"), yesNo(local.rolloverEnabled), yesNo(remote.rolloverEnabled))
                field("currency", mistiaLocalized(vi: "Tiền tệ", en: "Currency", ja: "通貨"), local.currencyCode, remote.currencyCode)
                field("archived", mistiaLocalized(vi: "Lưu trữ", en: "Archived", ja: "アーカイブ"), yesNo(local.isArchived), yesNo(remote.isArchived))
                field("deleted", mistiaLocalized(vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態"), deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.savingsGoal(let local), .savingsGoal(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("name", mistiaLocalized(vi: "Tên", en: "Name", ja: "名前"), local.name, remote.name)
                field("icon", mistiaLocalized(vi: "Icon", en: "Icon", ja: "アイコン"), local.iconSymbolName, remote.iconSymbolName)
                field("target", mistiaLocalized(vi: "Mục tiêu", en: "Target", ja: "目標額"), currency(local.targetMinor, code: local.currencyCode), currency(remote.targetMinor, code: remote.currencyCode))
                field("saved", mistiaLocalized(vi: "Đã tiết kiệm", en: "Saved", ja: "貯蓄済み"), currency(local.currentSavedMinor, code: local.currencyCode), currency(remote.currentSavedMinor, code: remote.currencyCode))
                field("targetDate", mistiaLocalized(vi: "Ngày mục tiêu", en: "Target date", ja: "目標日"), date(local.targetDate), date(remote.targetDate))
                field("wallet", mistiaLocalized(vi: "Ví liên kết", en: "Linked wallet", ja: "リンク済みウォレット"), uuid(local.linkedWalletID), uuid(remote.linkedWalletID))
                field("currency", mistiaLocalized(vi: "Tiền tệ", en: "Currency", ja: "通貨"), local.currencyCode, remote.currencyCode)
                field("sort", mistiaLocalized(vi: "Thứ tự", en: "Sort order", ja: "並び順"), number(local.sortOrder), number(remote.sortOrder))
                field("archived", mistiaLocalized(vi: "Lưu trữ", en: "Archived", ja: "アーカイブ"), yesNo(local.isArchived), yesNo(remote.isArchived))
                field("deleted", mistiaLocalized(vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態"), deleted(local.deletedAt), deleted(remote.deletedAt))
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
                localDeletedAt: local.deletedAt,
                remoteDeletedAt: remote.deletedAt
            )
        case (.installmentPlan(let local), .installmentPlan(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("name", mistiaLocalized(vi: "Tên", en: "Name", ja: "名前"), local.name, remote.name)
                field("icon", mistiaLocalized(vi: "Icon", en: "Icon", ja: "アイコン"), local.iconSymbolName, remote.iconSymbolName)
                field("amount", mistiaLocalized(vi: "Số tiền mỗi kỳ", en: "Amount per cycle", ja: "各回の金額"), currency(local.amountPerCycleMinor, code: local.currencyCode), currency(remote.amountPerCycleMinor, code: remote.currencyCode))
                field("dueDay", mistiaLocalized(vi: "Ngày đến hạn", en: "Due day", ja: "支払日"), number(local.dueDay), number(remote.dueDay))
                field("cycles", mistiaLocalized(vi: "Số kỳ", en: "Cycles", ja: "回数"), local.totalCycles.map(number), remote.totalCycles.map(number))
                field("frequency", mistiaLocalized(vi: "Chu kỳ tháng", en: "Monthly frequency", ja: "月単位の周期"), number(local.frequencyMonths), number(remote.frequencyMonths))
                field("wallet", mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット"), uuid(local.paymentWalletID), uuid(remote.paymentWalletID))
                field("currency", mistiaLocalized(vi: "Tiền tệ", en: "Currency", ja: "通貨"), local.currencyCode, remote.currencyCode)
                field("archived", mistiaLocalized(vi: "Lưu trữ", en: "Archived", ja: "アーカイブ"), yesNo(local.isArchived), yesNo(remote.isArchived))
                field("deleted", mistiaLocalized(vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態"), deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        case (.dueOccurrence(let local), .dueOccurrence(let remote)):
            return MistiaSyncConflictDifferenceBuilder.build {
                field("sourceKind", mistiaLocalized(vi: "Nguồn", en: "Source", ja: "ソース"), local.sourceKindRawValue, remote.sourceKindRawValue)
                field("source", mistiaLocalized(vi: "Nguồn", en: "Source", ja: "ソース"), uuid(local.sourceID), uuid(remote.sourceID))
                field("month", mistiaLocalized(vi: "Tháng", en: "Month", ja: "月"), local.selectedMonthKey, remote.selectedMonthKey)
                field("scheduled", mistiaLocalized(vi: "Ngày dự kiến", en: "Scheduled date", ja: "予定日"), date(local.scheduledDate), date(remote.scheduledDate))
                field("amount", mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額"), local.amountMinorSnapshot.map(number), remote.amountMinorSnapshot.map(number))
                field("status", mistiaLocalized(vi: "Trạng thái", en: "Status", ja: "状態"), local.statusRawValue, remote.statusRawValue)
                field("paidAt", mistiaLocalized(vi: "Đã trả lúc", en: "Paid at", ja: "支払い日時"), date(local.paidAt), date(remote.paidAt))
                field("transaction", mistiaLocalized(vi: "Giao dịch liên kết", en: "Linked transaction", ja: "リンク済み取引"), uuid(local.linkedTransactionID), uuid(remote.linkedTransactionID))
                field("deleted", mistiaLocalized(vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態"), deleted(local.deletedAt), deleted(remote.deletedAt))
            }
        default:
            return []
        }
    }

    func syncMetadataDifferences(comparedWith remote: MistiaSyncUploadRecord) -> [MistiaSyncConflictDifference] {
        MistiaSyncConflictDifferenceBuilder.build {
            field("updatedAt", mistiaLocalized(vi: "Cập nhật lúc", en: "Updated at", ja: "更新日時"), date(updatedAt), date(remote.updatedAt))
            field("version", mistiaLocalized(vi: "Sync version", en: "Sync version", ja: "同期バージョン"), number(syncVersion), number(remote.syncVersion))
            field("device", mistiaLocalized(vi: "Thiết bị sửa cuối", en: "Last modified device", ja: "最終更新端末"), uuid(lastModifiedByDeviceID), uuid(remote.lastModifiedByDeviceID))
            field("deletedAt", mistiaLocalized(vi: "Xóa lúc", en: "Deleted at", ja: "削除日時"), date(deletedAt), date(remote.deletedAt))
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
        localDeletedAt: Date?,
        remoteDeletedAt: Date?
    ) -> [MistiaSyncConflictDifference] {
        MistiaSyncConflictDifferenceBuilder.build {
            field("name", mistiaLocalized(vi: "Tên", en: "Name", ja: "名前"), localName, remoteName)
            field("icon", mistiaLocalized(vi: "Icon", en: "Icon", ja: "アイコン"), localIcon, remoteIcon)
            field("category", mistiaLocalized(vi: "Danh mục", en: "Category", ja: "カテゴリ"), uuid(localCategoryID), uuid(remoteCategoryID))
            field("amount", mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額"), localAmount.map { currency($0, code: localCurrencyCode) }, remoteAmount.map { currency($0, code: remoteCurrencyCode) })
            field("dueDay", mistiaLocalized(vi: "Ngày đến hạn", en: "Due day", ja: "支払日"), number(localDueDay), number(remoteDueDay))
            field("frequency", mistiaLocalized(vi: "Chu kỳ tháng", en: "Monthly frequency", ja: "月単位の周期"), number(localFrequency), number(remoteFrequency))
            field("wallet", mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット"), uuid(localPaymentWalletID), uuid(remotePaymentWalletID))
            field("currency", mistiaLocalized(vi: "Tiền tệ", en: "Currency", ja: "通貨"), localCurrencyCode, remoteCurrencyCode)
            field("archived", mistiaLocalized(vi: "Lưu trữ", en: "Archived", ja: "アーカイブ"), yesNo(localArchived), yesNo(remoteArchived))
            field("deleted", mistiaLocalized(vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態"), deleted(localDeletedAt), deleted(remoteDeletedAt))
        }
    }
}

private enum MistiaSyncConflictDifferenceBuilder {
    static func build(
        @MistiaSyncConflictDifferenceListBuilder _ body: () -> [MistiaSyncConflictDifference]
    ) -> [MistiaSyncConflictDifference] {
        body()
    }
}

@resultBuilder
private enum MistiaSyncConflictDifferenceListBuilder {
    static func buildBlock(_ components: [MistiaSyncConflictDifference]...) -> [MistiaSyncConflictDifference] {
        components.flatMap { $0 }
    }
}

private func field(
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

private func displayValue(_ value: String?) -> String {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return mistiaLocalized(vi: "Chưa có", en: "None", ja: "なし")
    }
    if UUID(uuidString: value) != nil {
        return mistiaLocalized(
            vi: "Không tìm thấy tên",
            en: "Name unavailable",
            ja: "名前なし"
        )
    }
    return value
}

private func firstNonEmpty(_ values: String?...) -> String? {
    values.first { value in
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } ?? nil
}

private func compactJoined(_ values: String?...) -> String {
    values
        .compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: " • ")
}

private func number(_ value: Int) -> String {
    "\(value)"
}

private func number(_ value: Int64) -> String {
    "\(value)"
}

private func currency(_ amountMinor: Int64, code: String) -> String {
    amountMinor.formattedCurrency(code: code)
}

private func formattedPlainAmount(_ amount: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
}

private func date(_ value: Date?) -> String? {
    value.map { MistiaDateFormatting.dateTimeString(for: $0) }
}

private func uuid(_ value: UUID?) -> String? {
    value.map { String($0.uuidString.lowercased().prefix(8)) }
}

private func yesNo(_ value: Bool) -> String {
    value
        ? mistiaLocalized(vi: "Có", en: "Yes", ja: "はい")
        : mistiaLocalized(vi: "Không", en: "No", ja: "いいえ")
}

private func deleted(_ value: Date?) -> String {
    if let value {
        return mistiaLocalized(
            vi: "Đã xóa lúc \(MistiaDateFormatting.dateTimeString(for: value))",
            en: "Deleted at \(MistiaDateFormatting.dateTimeString(for: value, language: .english))",
            ja: "\(MistiaDateFormatting.dateTimeString(for: value, language: .japanese)) に削除"
        )
    }
    return mistiaLocalized(vi: "Đang dùng", en: "Active", ja: "有効")
}

private func recordState(isArchived: Bool, deletedAt: Date?) -> String {
    if deletedAt != nil {
        return mistiaLocalized(vi: "Đã xóa", en: "Deleted", ja: "削除済み")
    }
    if isArchived {
        return mistiaLocalized(vi: "Đã lưu trữ", en: "Archived", ja: "アーカイブ済み")
    }
    return mistiaLocalized(vi: "Đang active", en: "Active", ja: "有効")
}

private func version(_ value: Int64) -> String {
    "v\(value)"
}

private func rawPayloadDifferences(
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

private func rawPayloadFields(_ json: String) -> [String: String] {
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

private func readableFieldName(_ key: String) -> String {
    switch key.lowercased() {
    case "wallet_id":
        return mistiaLocalized(vi: "Ví", en: "Wallet", ja: "ウォレット")
    case "source_wallet_id":
        return mistiaLocalized(vi: "Ví nguồn", en: "Source wallet", ja: "出金ウォレット")
    case "destination_wallet_id":
        return mistiaLocalized(vi: "Ví đích", en: "Destination wallet", ja: "入金ウォレット")
    case "payment_wallet_id":
        return mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット")
    case "linked_wallet_id":
        return mistiaLocalized(vi: "Ví liên kết", en: "Linked wallet", ja: "リンク済みウォレット")
    case "category_id":
        return mistiaLocalized(vi: "Danh mục", en: "Category", ja: "カテゴリ")
    case "parent_category_id":
        return mistiaLocalized(vi: "Danh mục cha", en: "Parent category", ja: "親カテゴリ")
    case "transaction_id", "linked_transaction_id":
        return mistiaLocalized(vi: "Giao dịch", en: "Transaction", ja: "取引")
    case "source_id":
        return mistiaLocalized(vi: "Nguồn", en: "Source", ja: "ソース")
    default:
        break
    }

    return key
        .split(separator: "_")
        .filter { $0.lowercased() != "id" && $0.lowercased() != "uid" }
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}
