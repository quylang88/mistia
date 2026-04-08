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
}
