import Foundation

nonisolated enum MistiaProfileAvatarCache {
    static func cachedAvatarURL(for userID: UUID) -> URL? {
        cachedAvatarURLMap(forUserIDs: [userID])[userID]
    }

    static func loadCachedAvatarURLMap(for userIDs: [UUID]) async -> [UUID: URL] {
        let uniqueUserIDs = Set(userIDs)
        guard !uniqueUserIDs.isEmpty else { return [:] }

        return await Task.detached(priority: .utility) {
            cachedAvatarURLMap(forUserIDs: uniqueUserIDs)
        }.value
    }

    private static func cachedAvatarURLMap(forUserIDs userIDs: Set<UUID>) -> [UUID: URL] {
        guard let directoryURL = try? avatarDirectoryURL(create: false) else { return [:] }
        guard let cachedFiles = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return [:]
        }

        var latestByUserID: [UUID: (url: URL, modifiedAt: Date)] = [:]
        for fileURL in cachedFiles {
            let fileName = fileURL.lastPathComponent
            guard let separatorIndex = fileName.firstIndex(of: ".") else { continue }
            let userIDString = String(fileName[..<separatorIndex])
            guard let userID = UUID(uuidString: userIDString),
                  userIDs.contains(userID) else {
                continue
            }

            let modifiedAt = (try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            if let existing = latestByUserID[userID], existing.modifiedAt >= modifiedAt {
                continue
            }
            latestByUserID[userID] = (fileURL, modifiedAt)
        }

        return latestByUserID.mapValues { $0.url }
    }

    static func cachedAvatarURL(forFileName fileName: String) -> URL? {
        guard let directoryURL = try? avatarDirectoryURL(create: false) else { return nil }
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    static func cacheRemoteAvatarIfNeeded(
        from remoteURL: URL?,
        for userID: UUID
    ) async -> URL? {
        guard let remoteURL, !remoteURL.isFileURL else {
            return remoteURL
        }

        if let cachedURL = cachedAvatarURL(for: userID) {
            return cachedURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  !data.isEmpty else {
                return nil
            }

            let fileName = try saveRemoteAvatarImageData(
                data,
                mimeType: httpResponse.mimeType,
                sourceURL: remoteURL,
                for: userID
            )
            return cachedAvatarURL(forFileName: fileName)
        } catch {
            return nil
        }
    }

    static func saveRemoteAvatarImageData(
        _ data: Data,
        mimeType: String?,
        sourceURL: URL,
        for userID: UUID
    ) throws -> String {
        let directoryURL = try avatarDirectoryURL(create: true)
        let fileExtension = avatarFileExtension(mimeType: mimeType, sourceURL: sourceURL)
        let fileName = "\(userID.uuidString.lowercased()).\(fileExtension)"
        try removeCachedAvatarFiles(for: userID, keeping: fileName, in: directoryURL)

        let fileURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    private static func avatarDirectoryURL(create: Bool) throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let directoryURL = baseURL.appendingPathComponent("ProfileAvatars", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    private static func avatarFileExtension(mimeType: String?, sourceURL: URL) -> String {
        let trimmedExtension = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedExtension.isEmpty {
            return trimmedExtension.lowercased()
        }

        switch mimeType?.lowercased() {
        case "image/png":
            return "png"
        case "image/heic", "image/heif":
            return "heic"
        case "image/webp":
            return "webp"
        case "image/gif":
            return "gif"
        default:
            return "jpg"
        }
    }

    private static func removeCachedAvatarFiles(
        for userID: UUID,
        keeping keptFileName: String,
        in directoryURL: URL
    ) throws {
        let filePrefix = userID.uuidString.lowercased() + "."
        let cachedFiles = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for fileURL in cachedFiles where fileURL.lastPathComponent.hasPrefix(filePrefix)
            && fileURL.lastPathComponent != keptFileName {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
