import Foundation

enum MistiaLegacyStoreRecovery {
    struct RecoveryError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    static func canRecover(from error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == 134504
    }

    static func recoveredStoreURL(for primaryStoreURL: URL) -> URL {
        let directoryURL = primaryStoreURL.deletingLastPathComponent()
        let baseName = primaryStoreURL.deletingPathExtension().lastPathComponent
        return directoryURL
            .appendingPathComponent("\(baseName).recovered")
            .appendingPathExtension(primaryStoreURL.pathExtension)
    }

    static func recoverLegacyStoreIfNeeded(
        at legacyStoreURL: URL,
        recoveredStoreURL: URL
    ) throws -> Bool {
        _ = legacyStoreURL
        _ = recoveredStoreURL
        return false
    }

    static func recoverStore(at legacyStoreURL: URL, recoveredStoreURL: URL) throws {
        _ = legacyStoreURL
        _ = recoveredStoreURL
        throw RecoveryError(message: "Legacy store recovery has been removed for the release build.")
    }
}
