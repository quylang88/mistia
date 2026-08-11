import Foundation

nonisolated final class InvestmentProductImageStore: @unchecked Sendable {
    private struct Manifest: Codable {
        var pendingUploads: Set<String> = []
        var deferredDeletionsByAssetID: [String: Set<String>] = [:]
        var readyDeletions: Set<String> = []
    }

    private static let lock = NSLock()
    private let fileManager: FileManager
    let baseDirectory: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory ?? Self.defaultBaseDirectory(fileManager: fileManager)
    }

    static func defaultBaseDirectory(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return support
            .appending(path: "Mistia", directoryHint: .isDirectory)
            .appending(path: "InvestmentProductImages", directoryHint: .isDirectory)
    }

    func stageReplacement(
        ownerUserID: UUID,
        assetID: UUID,
        jpegData: Data,
        thumbnailData: Data,
        replacing oldPath: String?
    ) throws -> String {
        let path = [
            ownerUserID.uuidString.lowercased(),
            assetID.uuidString.lowercased(),
            "\(UUID().uuidString.lowercased()).jpg"
        ].joined(separator: "/")

        try Self.withLock {
            try ensureDirectories(for: path)
            try jpegData.write(to: imageURL(for: path), options: .atomic)
            try thumbnailData.write(to: thumbnailURL(for: path), options: .atomic)
            var manifest = try loadManifest()
            manifest.pendingUploads.insert(path)
            if let oldPath, oldPath != path, isSafeObjectPath(oldPath) {
                if manifest.pendingUploads.remove(oldPath) != nil {
                    try? removeCachedFiles(for: oldPath)
                } else {
                    manifest.deferredDeletionsByAssetID[assetID.uuidString.lowercased(), default: []]
                        .insert(oldPath)
                }
            }
            try saveManifest(manifest)
        }
        return path
    }

    func stageRemoval(assetID: UUID, path: String?) throws {
        guard let path, isSafeObjectPath(path) else { return }
        try Self.withLock {
            var manifest = try loadManifest()
            if manifest.pendingUploads.remove(path) != nil {
                try? removeCachedFiles(for: path)
            } else {
                manifest.deferredDeletionsByAssetID[assetID.uuidString.lowercased(), default: []]
                    .insert(path)
            }
            try saveManifest(manifest)
        }
    }

    func uploadData(for path: String) throws -> Data? {
        guard isSafeObjectPath(path) else { return nil }
        return try Self.withLock {
            let manifest = try loadManifest()
            guard manifest.pendingUploads.contains(path) else { return nil }
            return try Data(contentsOf: imageURL(for: path))
        }
    }

    func markUploadSucceeded(for path: String) throws {
        try Self.withLock {
            var manifest = try loadManifest()
            manifest.pendingUploads.remove(path)
            try saveManifest(manifest)
        }
    }

    func markAssetUpdateSucceeded(assetID: UUID) throws {
        try Self.withLock {
            var manifest = try loadManifest()
            let key = assetID.uuidString.lowercased()
            manifest.readyDeletions.formUnion(manifest.deferredDeletionsByAssetID.removeValue(forKey: key) ?? [])
            try saveManifest(manifest)
        }
    }

    func pendingDeletionPaths() throws -> [String] {
        try Self.withLock { Array(try loadManifest().readyDeletions).sorted() }
    }

    func markDeletionSucceeded(for path: String) throws {
        try Self.withLock {
            var manifest = try loadManifest()
            manifest.readyDeletions.remove(path)
            try? removeCachedFiles(for: path)
            try saveManifest(manifest)
        }
    }

    func cachedImageData(for path: String) throws -> Data? {
        guard isSafeObjectPath(path) else { return nil }
        return try Self.withLock {
            let url = imageURL(for: path)
            return fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        }
    }

    func cachedThumbnailData(for path: String) throws -> Data? {
        guard isSafeObjectPath(path) else { return nil }
        return try Self.withLock {
            let thumbnail = thumbnailURL(for: path)
            if fileManager.fileExists(atPath: thumbnail.path) {
                return try Data(contentsOf: thumbnail)
            }
            let image = imageURL(for: path)
            return fileManager.fileExists(atPath: image.path) ? try Data(contentsOf: image) : nil
        }
    }

    func cacheDownloadedJPEG(
        _ data: Data,
        thumbnailData: Data? = nil,
        for path: String
    ) throws {
        guard isSafeObjectPath(path) else { return }
        try Self.withLock {
            try ensureDirectories(for: path)
            try data.write(to: imageURL(for: path), options: .atomic)
            if !fileManager.fileExists(atPath: thumbnailURL(for: path).path) {
                try (thumbnailData ?? data).write(to: thumbnailURL(for: path), options: .atomic)
            }
        }
    }

    private static func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private var manifestURL: URL { baseDirectory.appending(path: "manifest.json") }
    private var imagesDirectory: URL { baseDirectory.appending(path: "images", directoryHint: .isDirectory) }
    private var thumbnailsDirectory: URL { baseDirectory.appending(path: "thumbnails", directoryHint: .isDirectory) }

    private func imageURL(for path: String) -> URL { imagesDirectory.appending(path: path) }
    private func thumbnailURL(for path: String) -> URL { thumbnailsDirectory.appending(path: path) }

    private func ensureDirectories(for path: String) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: imageURL(for: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: thumbnailURL(for: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func loadManifest() throws -> Manifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return Manifest() }
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    }

    private func saveManifest(_ manifest: Manifest) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private func removeCachedFiles(for path: String) throws {
        for url in [imageURL(for: path), thumbnailURL(for: path)] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func isSafeObjectPath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.split(separator: "/").contains("..")
            && path.lowercased().hasSuffix(".jpg")
    }
}
