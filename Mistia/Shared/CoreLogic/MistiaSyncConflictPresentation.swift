import Foundation

nonisolated enum MistiaSyncConflictPresentation {
    static func visibleDifferences(
        from differences: [MistiaSyncConflictDifference],
        semanticLimit: Int = 3,
        fallbackLimit: Int = 2
    ) -> [MistiaSyncConflictDifference] {
        let userFacingDifferences = differences.filter { !isInternalField($0.id) }
        let semanticDifferences = userFacingDifferences.filter { !isMetadataField($0.id) }

        if !semanticDifferences.isEmpty {
            return Array(semanticDifferences.prefix(semanticLimit))
        }

        return Array(userFacingDifferences.prefix(fallbackLimit))
    }

    static func isInternalField(_ id: String) -> Bool {
        let normalized = normalizedFieldID(id)
        return normalized == "id"
            || normalized == "uid"
            || normalized == "recordid"
            || normalized.hasSuffix("userid")
            || normalized.hasSuffix("deviceid")
            || normalized == "device"
            || normalized.contains("device")
            || normalized == "systemkey"
            || normalized == "synckey"
            || normalized == "syncversion"
            || normalized == "version"
    }

    static func isMetadataField(_ id: String) -> Bool {
        let normalized = normalizedFieldID(id)
        return normalized == "updatedat"
            || normalized == "deletedat"
            || normalized == "createdat"
            || normalized == "archivedat"
    }

    private static func normalizedFieldID(_ id: String) -> String {
        id
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }
}
