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

    static func descriptor(for rawSystemKey: String?) -> MistiaSystemCategoryDescriptor? {
        guard let rawSystemKey else { return nil }

        if let parentKey = MistiaSystemCategoryParentKey(rawValue: rawSystemKey) {
            return MistiaSystemCategoryDescriptor(
                rawSystemKey: rawSystemKey,
                kind: parentKey.kind,
                iconSymbolName: parentKey.iconSymbolName,
                fallbackIconSymbolName: parentKey.fallbackSystemName,
                iconColorHex: MistiaIconColorPalette.presetHex(forDefault: parentKey.iconColorHex),
                hierarchyRole: .parent,
                knownNames: parentKey.knownDefaultNames(),
                defaultParentSystemKey: nil,
                startsArchived: false,
                sortOrder: MistiaSystemCategoryParentKey.activeDefaults.firstIndex(of: parentKey)
            )
        }

        guard let systemKey = MistiaSystemCategoryKey(rawValue: rawSystemKey) else {
            return nil
        }

        return MistiaSystemCategoryDescriptor(
            rawSystemKey: rawSystemKey,
            kind: systemKey.kind,
            iconSymbolName: systemKey.iconSymbolName,
            fallbackIconSymbolName: systemKey.fallbackSystemName,
            iconColorHex: MistiaIconColorPalette.presetHex(forDefault: systemKey.iconColorHex),
            hierarchyRole: .child,
            knownNames: systemKey.knownDefaultNames(),
            defaultParentSystemKey: defaultParentKey(for: systemKey).rawValue,
            startsArchived: !systemKey.isActiveDefault,
            sortOrder: MistiaSystemCategoryKey.activeDefaults.firstIndex(of: systemKey)
        )
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

    private static func defaultParentKey(
        for systemKey: MistiaSystemCategoryKey
    ) -> MistiaSystemCategoryParentKey {
        systemKey.parentKey ?? uncategorizedParentKey(for: systemKey.kind)
    }

    private static func uncategorizedParentKey(
        for kind: TransactionCategoryKind
    ) -> MistiaSystemCategoryParentKey {
        switch kind {
        case .expense:
            .expenseOther
        case .income:
            .incomeOther
        }
    }
}
