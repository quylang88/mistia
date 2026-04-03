import Foundation

struct MistiaGoogleSignInConfiguration: Equatable {
    let clientID: String
    let serverClientID: String
    let callbackScheme: String

    var isPlaceholder: Bool {
        Self.isPlaceholderValue(clientID) || Self.isPlaceholderValue(serverClientID)
    }

    func isURLSchemeRegistered(bundle: Bundle = .main) -> Bool {
        Self.registeredURLSchemes(bundle: bundle).contains(callbackScheme)
    }

    static func load(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> MistiaGoogleSignInConfiguration? {
        guard
            let clientID = resolvedValue(
                bundleKey: "GIDClientID",
                environmentKey: "MISTIA_GOOGLE_IOS_CLIENT_ID",
                bundle: bundle,
                processInfo: processInfo
            ),
            let serverClientID = resolvedValue(
                bundleKey: "GIDServerClientID",
                environmentKey: "MISTIA_GOOGLE_SERVER_CLIENT_ID",
                bundle: bundle,
                processInfo: processInfo
            )
        else {
            return nil
        }

        return MistiaGoogleSignInConfiguration(
            clientID: clientID,
            serverClientID: serverClientID,
            callbackScheme: reversedClientID(from: clientID)
        )
    }

    static func clientID(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> String? {
        resolvedValue(
            bundleKey: "GIDClientID",
            environmentKey: "MISTIA_GOOGLE_IOS_CLIENT_ID",
            bundle: bundle,
            processInfo: processInfo
        )
    }

    static func serverClientID(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> String? {
        resolvedValue(
            bundleKey: "GIDServerClientID",
            environmentKey: "MISTIA_GOOGLE_SERVER_CLIENT_ID",
            bundle: bundle,
            processInfo: processInfo
        )
    }

    static func reversedClientID(from clientID: String) -> String {
        clientID
            .split(separator: ".")
            .reversed()
            .joined(separator: ".")
    }

    static func registeredURLSchemes(bundle: Bundle = .main) -> Set<String> {
        guard
            let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        else {
            return []
        }

        let schemes = urlTypes
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Set(schemes)
    }

    private static func resolvedValue(
        bundleKey: String,
        environmentKey: String,
        bundle: Bundle,
        processInfo: ProcessInfo
    ) -> String? {
        if let environmentValue = sanitizedValue(processInfo.environment[environmentKey]) {
            return environmentValue
        }

        return sanitizedValue(bundle.object(forInfoDictionaryKey: bundleKey) as? String)
    }

    private static func sanitizedValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPlaceholderValue(trimmed) else {
            return nil
        }
        return trimmed
    }

    private static func isPlaceholderValue(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty
            || normalized.contains("YOUR_GOOGLE")
            || normalized.contains("REPLACE_WITH")
            || normalized.contains("REPLACE-ME")
            || normalized.contains("PLACEHOLDER")
    }
}
