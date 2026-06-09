import CryptoKit
import Foundation

struct MistiaSystemCategoryDescriptor: Equatable {
    let rawSystemKey: String
    let kind: TransactionCategoryKind
    let iconSymbolName: String
    let fallbackIconSymbolName: String?
    let iconColorHex: String
    let hierarchyRole: TransactionCategoryHierarchyRole
    let knownNames: [String]
    let defaultParentSystemKey: String?
    let startsArchived: Bool
    let sortOrder: Int?
}

nonisolated enum MistiaSystemCategoryIdentity {
    private static let namespace = "vn.com.quyln.mistia.system-category"

    static func canonicalID(for rawSystemKey: String) -> UUID {
        stableUUID(for: "\(namespace).\(rawSystemKey)")
    }

    static func canonicalID(for systemKey: MistiaSystemCategoryKey) -> UUID {
        canonicalID(for: systemKey.rawValue)
    }

    static func canonicalID(for parentKey: MistiaSystemCategoryParentKey) -> UUID {
        canonicalID(for: parentKey.rawValue)
    }

    static func familyScopedID(
        remoteCategoryID: UUID,
        ownerUserID: UUID
    ) -> UUID {
        stableUUID(
            for: "\(namespace).family.\(ownerUserID.uuidString.lowercased()).\(remoteCategoryID.uuidString.lowercased())"
        )
    }

    static func cloudScopedID(
        canonicalCategoryID: UUID,
        ownerUserID: UUID
    ) -> UUID {
        stableUUID(
            for: "\(namespace).cloud.\(ownerUserID.uuidString.lowercased()).\(canonicalCategoryID.uuidString.lowercased())"
        )
    }

    static var balanceAdjustmentExpenseID: UUID {
        canonicalID(for: .balanceAdjustmentExpense)
    }

    static var balanceAdjustmentIncomeID: UUID {
        canonicalID(for: .balanceAdjustmentIncome)
    }

    static func descriptor(for rawSystemKey: String?) -> MistiaSystemCategoryDescriptor? {
        guard let rawSystemKey,
              let parsed = MistiaSystemCategoryRegistry.shared.category(for: rawSystemKey) else {
            return nil
        }

        let parentId = MistiaSystemCategoryRegistry.shared.parentId(for: rawSystemKey)
        let isParent = parentId == nil

        if isParent {
            let activeParents = MistiaSystemCategoryRegistry.shared.allParents.filter { $0.active }
            let sortOrder = activeParents.firstIndex(where: { $0.id == rawSystemKey })
            return MistiaSystemCategoryDescriptor(
                rawSystemKey: rawSystemKey,
                kind: parsed.kind(in: MistiaSystemCategoryRegistry.shared),
                iconSymbolName: parsed.icon,
                fallbackIconSymbolName: parsed.fallbackIcon,
                iconColorHex: MistiaIconColorPalette.presetHex(forDefault: parsed.color),
                hierarchyRole: .parent,
                knownNames: parsed.knownDefaultNames(),
                defaultParentSystemKey: nil,
                startsArchived: false,
                sortOrder: sortOrder
            )
        } else {
            let activeChildren = MistiaSystemCategoryRegistry.shared.allParents
                .flatMap { $0.children ?? [] }
                .filter { $0.active }
            let sortOrder = activeChildren.firstIndex(where: { $0.id == rawSystemKey })
            return MistiaSystemCategoryDescriptor(
                rawSystemKey: rawSystemKey,
                kind: parsed.kind(in: MistiaSystemCategoryRegistry.shared),
                iconSymbolName: parsed.icon,
                fallbackIconSymbolName: parsed.fallbackIcon,
                iconColorHex: MistiaIconColorPalette.presetHex(forDefault: parsed.color),
                hierarchyRole: .child,
                knownNames: parsed.knownDefaultNames(),
                defaultParentSystemKey: parentId,
                startsArchived: !parsed.active,
                sortOrder: sortOrder
            )
        }
    }

    private static func stableUUID(for value: String) -> UUID {
        let digest = Insecure.SHA1.hash(data: Data(value.utf8))
        let bytes = Array(digest)
        precondition(bytes.count >= 16)

        let uuidBytes: [UInt8] = Array(bytes.prefix(16)).enumerated().map { index, byte in
            switch index {
            case 6:
                return (byte & 0x0F) | 0x50
            case 8:
                return (byte & 0x3F) | 0x80
            default:
                return byte
            }
        }

        return uuidBytes.withUnsafeBytes { rawBuffer in
            let tuple = rawBuffer.bindMemory(to: uuid_t.self)
            return UUID(uuid: tuple[0])
        }
    }


}
