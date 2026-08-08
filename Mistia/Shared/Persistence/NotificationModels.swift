import Foundation
import SwiftData

enum MistiaAppNotificationSource: String, Codable, CaseIterable {
    case localReminder
    case system
    case remote
    case family
}

enum MistiaAppNotificationKind: String, Codable, CaseIterable {
    case dueSoon
    case budgetWarning
    case lowWallet
    case creditCardStatementReady
    case creditCardAutoPaymentSucceeded
    case creditCardAutoPaymentFailed
    case familyPlaceholder
    case permissionRequestReceived
    case permissionRequestApproved
    case permissionRequestRejected
    case permissionRevoked
    case permissionPolicyChanged
    case familyTransactionRequestReceived
    case familyTransactionRequestApproved
    case familyTransactionRequestRejected
    case familyActivity
    case accessIssue
    case billPaymentRequired
    case billAutoPaymentSucceeded
    case billAutoPaymentFailed
    case billOverdue
}

nonisolated enum MistiaFamilyNotificationResourceType: String, Codable, CaseIterable {
    case wallet
    case category
    case budget
    case goal
    case card
    case debt
    case familyTransfer = "family_transfer"
    case transaction
    case permission
    case bill
    case due
    case installment
    case event
    case investment

    var localizedName: String {
        switch self {
        case .wallet:
            return L10n.shared.persistence.notification.wallet
        case .category:
            return L10n.shared.persistence.notification.category
        case .budget:
            return L10n.shared.persistence.notification.budget
        case .goal:
            return L10n.shared.persistence.notification.goal
        case .card:
            return L10n.shared.persistence.notification.card
        case .debt:
            return L10n.shared.persistence.notification.debt
        case .familyTransfer:
            return L10n.shared.persistence.notification.familyTransfer
        case .transaction:
            return L10n.shared.persistence.notification.transaction
        case .permission:
            return L10n.shared.persistence.notification.permission
        case .bill:
            return L10n.shared.persistence.notification.bill
        case .due:
            return L10n.shared.persistence.notification.paymentPlan
        case .installment:
            return L10n.shared.persistence.notification.installment
        case .event:
            return L10n.shared.persistence.notification.event
        case .investment:
            return L10n.shared.persistence.notification.investment
        }
    }
}

nonisolated enum MistiaFamilyPermissionScope: String, Codable, CaseIterable {
    case use
    case edit
    case create
    case view

    var localizedActionName: String {
        switch self {
        case .use:
            return L10n.shared.persistence.notification.use
        case .edit:
            return L10n.shared.persistence.notification.edit
        case .create:
            return L10n.shared.persistence.notification.create
        case .view:
            return L10n.shared.persistence.notification.view
        }
    }
}

enum MistiaNotificationActionState: String, Codable, CaseIterable {
    case informational
    case pending
    case approved
    case rejected
    case revoked
    case canceled
    case resolved
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
        key: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String,
        body: String,
        kind: MistiaAppNotificationKind,
        source: MistiaAppNotificationSource,
        isRead: Bool = false,
        actionRoute: String? = nil,
        recipientUserID: UUID? = nil,
        actorUserID: UUID? = nil,
        familyID: UUID? = nil,
        resourceType: MistiaFamilyNotificationResourceType? = nil,
        resourceID: UUID? = nil,
        permissionScope: MistiaFamilyPermissionScope? = nil,
        permissionRequestID: UUID? = nil,
        actionState: MistiaNotificationActionState? = nil,
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
        self.kindRawValue = kind.rawValue
        self.sourceRawValue = source.rawValue
        self.isRead = isRead
        self.actionRoute = actionRoute
        self.recipientUserID = recipientUserID
        self.actorUserID = actorUserID
        self.familyID = familyID
        self.resourceTypeRawValue = resourceType?.rawValue
        self.resourceID = resourceID
        self.permissionScopeRawValue = permissionScope?.rawValue
        self.permissionRequestID = permissionRequestID
        self.actionStateRawValue = actionState?.rawValue
        self.readAt = readAt
        self.metadataJSON = metadataJSON
        self.remoteVersion = remoteVersion
        self.needsReadSync = needsReadSync
    }

    var kind: MistiaAppNotificationKind {
        get { MistiaAppNotificationKind(rawValue: kindRawValue) ?? .dueSoon }
        set { kindRawValue = newValue.rawValue }
    }

    var source: MistiaAppNotificationSource {
        get { MistiaAppNotificationSource(rawValue: sourceRawValue) ?? .system }
        set { sourceRawValue = newValue.rawValue }
    }

    var resourceType: MistiaFamilyNotificationResourceType? {
        get { resourceTypeRawValue.flatMap(MistiaFamilyNotificationResourceType.init(rawValue:)) }
        set { resourceTypeRawValue = newValue?.rawValue }
    }

    var permissionScope: MistiaFamilyPermissionScope? {
        get { permissionScopeRawValue.flatMap(MistiaFamilyPermissionScope.init(rawValue:)) }
        set { permissionScopeRawValue = newValue?.rawValue }
    }

    var actionState: MistiaNotificationActionState {
        get { actionStateRawValue.flatMap(MistiaNotificationActionState.init(rawValue:)) ?? .informational }
        set { actionStateRawValue = newValue.rawValue }
    }
}

// MARK: - Due-action notification payload

nonisolated struct DueNotificationActionPayload: Codable {
    let sourceKind: String       // PlanningDueSourceKind raw value
    let sourceID: UUID
    let dueMonthKey: String
    let dueDate: Date
    let requiresAmountInput: Bool
    let currencyCode: String
    let billName: String
    let linkedPaymentWalletID: UUID?

    enum CodingKeys: String, CodingKey {
        case sourceKind
        case sourceID = "sourceId"
        case dueMonthKey
        case dueDate
        case requiresAmountInput
        case currencyCode
        case billName
        case linkedPaymentWalletID = "linkedPaymentWalletId"
    }
}

enum CreditCardNotificationActionKind: String, Codable, CaseIterable {
    case statementReady
    case autoPaymentSucceeded
    case autoPaymentFailed
}

nonisolated struct CreditCardNotificationActionPayload: Codable {
    let actionKind: CreditCardNotificationActionKind
    let statementMonthKey: String
    let dueDate: Date
    let linkedPaymentWalletID: UUID?
    let walletName: String
    let currencyCode: String

    enum CodingKeys: String, CodingKey {
        case actionKind
        case statementMonthKey
        case dueDate
        case linkedPaymentWalletID = "linkedPaymentWalletId"
        case walletName
        case currencyCode
    }
}

extension AppNotificationRecord {
    private func decodeMetadata<T: Decodable>(_ type: T.Type) -> T? {
        guard let json = metadataJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder.mistiaSyncDecoder.decode(type, from: data)
    }

    var dueActionPayload: DueNotificationActionPayload? {
        decodeMetadata(DueNotificationActionPayload.self)
    }

    var creditCardActionPayload: CreditCardNotificationActionPayload? {
        decodeMetadata(CreditCardNotificationActionPayload.self)
    }

    var isBillActionableNotification: Bool {
        switch kind {
        case .billPaymentRequired, .billAutoPaymentFailed, .billOverdue:
            return true
        default:
            return false
        }
    }

    var topUpTransferDestinationWalletID: UUID? {
        switch kind {
        case .creditCardAutoPaymentFailed:
            creditCardActionPayload?.linkedPaymentWalletID
        case .billAutoPaymentFailed:
            dueActionPayload?.linkedPaymentWalletID
        default:
            nil
        }
    }
}

struct AppNotificationRecord_Extension {}

struct FamilyNotificationRemoteRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceEventKey: String
    let familyID: UUID
    let userID: UUID
    let actorUserID: UUID?
    let kindRawValue: String
    let resourceTypeRawValue: String?
    let resourceID: UUID?
    let permissionScopeRawValue: String?
    let permissionRequestID: UUID?
    let actionStateRawValue: String
    let title: String
    let body: String
    let metadata: [String: String]?
    let readAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let syncVersion: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case sourceEventKey = "source_event_key"
        case familyID = "family_id"
        case userID = "user_id"
        case actorUserID = "actor_user_id"
        case kindRawValue = "kind"
        case resourceTypeRawValue = "resource_type"
        case resourceID = "resource_id"
        case permissionScopeRawValue = "permission_scope"
        case permissionRequestID = "permission_request_id"
        case actionStateRawValue = "action_state"
        case title
        case body
        case metadata
        case readAt = "read_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncVersion = "sync_version"
    }

    var kind: MistiaAppNotificationKind {
        switch kindRawValue {
        case "permission_request_received":
            return .permissionRequestReceived
        case "permission_request_approved":
            return .permissionRequestApproved
        case "permission_request_rejected":
            return .permissionRequestRejected
        case "permission_revoked":
            return .permissionRevoked
        case "permission_policy_changed":
            return .permissionPolicyChanged
        case "transaction_request_received":
            return .familyTransactionRequestReceived
        case "transaction_request_approved":
            return .familyTransactionRequestApproved
        case "transaction_request_rejected":
            return .familyTransactionRequestRejected
        case "family_activity":
            return .familyActivity
        case "access_issue":
            return .accessIssue
        default:
            return .familyPlaceholder
        }
    }

    var resourceType: MistiaFamilyNotificationResourceType? {
        resourceTypeRawValue.flatMap(MistiaFamilyNotificationResourceType.init(rawValue:))
    }

    var permissionScope: MistiaFamilyPermissionScope? {
        permissionScopeRawValue.flatMap(MistiaFamilyPermissionScope.init(rawValue:))
    }

    var actionState: MistiaNotificationActionState {
        MistiaNotificationActionState(rawValue: actionStateRawValue) ?? .informational
    }
}

extension FamilyNotificationRemoteRecord {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceEventKey = try container.decode(String.self, forKey: .sourceEventKey)
        familyID = try container.decode(UUID.self, forKey: .familyID)
        userID = try container.decode(UUID.self, forKey: .userID)
        actorUserID = try container.decodeIfPresent(UUID.self, forKey: .actorUserID)
        kindRawValue = try container.decode(String.self, forKey: .kindRawValue)
        resourceTypeRawValue = try container.decodeIfPresent(String.self, forKey: .resourceTypeRawValue)
        resourceID = try container.decodeIfPresent(UUID.self, forKey: .resourceID)
        permissionScopeRawValue = try container.decodeIfPresent(String.self, forKey: .permissionScopeRawValue)
        permissionRequestID = try container.decodeIfPresent(UUID.self, forKey: .permissionRequestID)
        actionStateRawValue = try container.decodeIfPresent(String.self, forKey: .actionStateRawValue)
            ?? MistiaNotificationActionState.informational.rawValue
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)

        if let decodedMetadata = try container.decodeIfPresent(
            [String: FamilyNotificationMetadataValue].self,
            forKey: .metadata
        ) {
            let stringMetadata = decodedMetadata.reduce(into: [String: String]()) { result, entry in
                if let value = entry.value.stringValue {
                    result[entry.key] = value
                }
            }
            metadata = stringMetadata.isEmpty ? nil : stringMetadata
        } else {
            metadata = nil
        }

        readAt = try container.decodeIfPresent(Date.self, forKey: .readAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
    }
}

private struct FamilyNotificationMetadataValue: Decodable {
    let stringValue: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            stringValue = nil
        } else if let value = try? container.decode(String.self) {
            stringValue = value
        } else if let value = try? container.decode(Int64.self) {
            stringValue = String(value)
        } else if let value = try? container.decode(Double.self), value.isFinite {
            stringValue = String(value)
        } else if let value = try? container.decode(Bool.self) {
            stringValue = value ? "true" : "false"
        } else {
            stringValue = nil
        }
    }
}

nonisolated struct FamilyPermissionRequestRemoteRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let familyID: UUID
    let requesterUserID: UUID
    let recipientUserID: UUID
    let resourceTypeRawValue: String
    let resourceID: UUID?
    let permissionScopeRawValue: String
    let statusRawValue: String
    let message: String?
    let respondedByUserID: UUID?
    let respondedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case requesterUserID = "requester_user_id"
        case recipientUserID = "recipient_user_id"
        case resourceTypeRawValue = "resource_type"
        case resourceID = "resource_id"
        case permissionScopeRawValue = "permission_scope"
        case statusRawValue = "status"
        case message
        case respondedByUserID = "responded_by_user_id"
        case respondedAt = "responded_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FamilyPermissionRequestInput: Encodable, Equatable {
    let familyID: UUID
    let recipientUserID: UUID
    let resourceType: MistiaFamilyNotificationResourceType
    let resourceID: UUID?
    let permissionScope: MistiaFamilyPermissionScope
    let title: String
    let body: String
    let message: String?
}

enum MistiaNotificationStore {
    @discardableResult
    static func clearAll(in context: ModelContext) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<AppNotificationRecord>())
        for row in rows {
            context.delete(row)
        }
        try context.save()
        #if !SWIFT_PACKAGE
        MistiaNotificationBadgeManager.setBadgeCount(0)
        #endif
        return rows.count
    }

    static func applyRemoteNotifications(
        _ remoteRows: [FamilyNotificationRemoteRecord],
        currentUserID: UUID,
        in context: ModelContext
    ) throws {
        let familySourceRawValue = MistiaAppNotificationSource.family.rawValue
        let existingFamilyRows = try context.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.sourceRawValue == familySourceRawValue
                }
            )
        )
        var existingByID = Dictionary(existingFamilyRows.map { ($0.id, $0) }, uniquingKeysWith: latestNotification)
        var existingByKey = Dictionary(existingFamilyRows.map { ($0.key, $0) }, uniquingKeysWith: latestNotification)

        for remote in remoteRows where remote.userID == currentUserID {
            let row = existingByID[remote.id] ?? existingByKey[remote.sourceEventKey] ?? AppNotificationRecord(
                id: remote.id,
                key: remote.sourceEventKey,
                createdAt: remote.createdAt,
                updatedAt: remote.updatedAt,
                title: remote.title,
                body: remote.body,
                kind: remote.kind,
                source: .family,
                isRead: remote.readAt != nil,
                recipientUserID: remote.userID
            )

            if row.modelContext == nil {
                context.insert(row)
            }

            let localReadAt = row.readAt
            let resolvedReadAt = latestReadAt(localReadAt, remote.readAt)

            row.id = remote.id
            row.key = remote.sourceEventKey
            row.createdAt = remote.createdAt
            row.updatedAt = max(remote.updatedAt, row.updatedAt)
            row.title = remote.title
            row.body = remote.body
            row.kind = remote.kind
            row.source = .family
            row.isRead = resolvedReadAt != nil
            row.actionRoute = nil
            row.recipientUserID = remote.userID
            row.actorUserID = remote.actorUserID
            row.familyID = remote.familyID
            row.resourceType = remote.resourceType
            row.resourceID = remote.resourceID
            row.permissionScope = remote.permissionScope
            row.permissionRequestID = remote.permissionRequestID
            row.actionState = remote.actionState
            row.readAt = resolvedReadAt
            row.metadataJSON = metadataJSONString(remote.metadata)
            row.remoteVersion = remote.syncVersion
            row.needsReadSync = row.needsReadSync || (localReadAt != nil && remote.readAt == nil)

            existingByID[remote.id] = row
            existingByKey[remote.sourceEventKey] = row
        }

        try context.save()
        updateAppBadgeCount(in: context, userID: currentUserID)
    }

    nonisolated private static func latestNotification(
        _ lhs: AppNotificationRecord,
        _ rhs: AppNotificationRecord
    ) -> AppNotificationRecord {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    static func markAllAsRead(
        for userID: UUID?,
        in context: ModelContext
    ) throws -> [UUID] {
        let rows = try unreadRowsVisibleTo(userID, in: context)
        return try markAsRead(
            rows.filter { isVisible($0, to: userID) },
            in: context
        )
    }

    static func markAsRead(
        _ rows: [AppNotificationRecord],
        in context: ModelContext,
        updatesBadgeCount: Bool = true
    ) throws -> [UUID] {
        let now = Date()
        var remoteIDs: [UUID] = []
        var didUpdateReadState = false

        for row in rows where !row.isRead || row.readAt == nil {
            row.isRead = true
            row.readAt = row.readAt ?? now
            row.updatedAt = now
            didUpdateReadState = true

            if row.source == .family {
                row.needsReadSync = true
                remoteIDs.append(row.id)
            }
        }

        guard didUpdateReadState else {
            return []
        }

        try context.save()
        if updatesBadgeCount {
            updateAppBadgeCount(in: context, userID: rows.first?.recipientUserID)
        }
        return remoteIDs
    }

    static func pendingReadSyncIDs(
        for userID: UUID?,
        in context: ModelContext
    ) throws -> [UUID] {
        let familySourceRawValue = MistiaAppNotificationSource.family.rawValue
        return try context.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.sourceRawValue == familySourceRawValue
                        && row.needsReadSync
                        && row.readAt != nil
                }
            )
        )
            .filter { isVisible($0, to: userID) }
            .map(\.id)
    }

    static func clearReadSyncFlags(
        ids: [UUID],
        in context: ModelContext
    ) throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let rows = try context.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.needsReadSync
                }
            )
        )
        for row in rows where idSet.contains(row.id) {
            row.needsReadSync = false
        }
        try context.save()
    }

    static func unreadCount(
        rows: [AppNotificationRecord],
        userID: UUID?,
        referenceDate: Date = .now
    ) -> Int {
        rows.filter { isVisible($0, to: userID, referenceDate: referenceDate) && !$0.isRead }.count
    }

    static func unreadCount(
        in context: ModelContext,
        userID: UUID?,
        referenceDate: Date = .now
    ) -> Int {
        let rows = (try? unreadRowsVisibleTo(userID, in: context)) ?? []
        return rows.filter { isVisible($0, to: userID, referenceDate: referenceDate) }.count
    }

    static func visibleRows(
        _ rows: [AppNotificationRecord],
        userID: UUID?,
        referenceDate: Date = .now
    ) -> [AppNotificationRecord] {
        rows.filter { isVisible($0, to: userID, referenceDate: referenceDate) }
    }

    static func isVisible(
        _ row: AppNotificationRecord,
        to userID: UUID?,
        referenceDate: Date = .now,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard row.kind != .dueSoon else {
            return false
        }

        #if !SWIFT_PACKAGE
        if row.source == .family, !MistiaNotificationPreferences.familyEnabled(defaults: defaults) {
            return false
        }
        #else
        if row.source == .family, !defaults.bool(forKey: "mistia.notifications.group.family.enabled") {
            return false
        }
        #endif

        if (row.source == .localReminder || row.source == .system), row.createdAt > referenceDate {
            return false
        }

        if row.source == .localReminder || row.source == .system {
            guard let recipientUserID = row.recipientUserID else {
                return userID == nil
            }
            return recipientUserID == userID
        }

        guard let recipientUserID = row.recipientUserID else { return false }
        return recipientUserID == userID
    }

    private static func unreadRowsVisibleTo(
        _ userID: UUID?,
        in context: ModelContext
    ) throws -> [AppNotificationRecord] {
        let dueSoonRawValue = MistiaAppNotificationKind.dueSoon.rawValue

        if let userID {
            return try context.fetch(
                FetchDescriptor<AppNotificationRecord>(
                    predicate: #Predicate<AppNotificationRecord> { row in
                        !row.isRead
                            && row.kindRawValue != dueSoonRawValue
                            && row.recipientUserID == userID
                    }
                )
            )
        }

        let localReminderSourceRawValue = MistiaAppNotificationSource.localReminder.rawValue
        let systemSourceRawValue = MistiaAppNotificationSource.system.rawValue
        return try context.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    !row.isRead
                        && row.kindRawValue != dueSoonRawValue
                        && row.recipientUserID == nil
                        && (
                            row.sourceRawValue == localReminderSourceRawValue
                                || row.sourceRawValue == systemSourceRawValue
                        )
                }
            )
        )
    }

    private static func latestReadAt(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.none, .none):
            return nil
        case (.some(let lhs), .none):
            return lhs
        case (.none, .some(let rhs)):
            return rhs
        case (.some(let lhs), .some(let rhs)):
            return max(lhs, rhs)
        }
    }

    private static func metadataJSONString(_ metadata: [String: String]?) -> String? {
        guard let metadata, !metadata.isEmpty else { return nil }
        let encoder = JSONEncoder.mistiaSyncEncoder
        return try? String(data: encoder.encode(metadata), encoding: .utf8)
    }

    static func updateAppBadgeCount(
        in context: ModelContext,
        userID: UUID?
    ) {
        let count = unreadCount(in: context, userID: userID)
        #if !SWIFT_PACKAGE
        MistiaNotificationBadgeManager.setBadgeCount(count)
        #endif
    }
}
