import Foundation

struct MistiaSyncConfiguration: Equatable {
    let projectURL: URL
    let anonKey: String

    var authBaseURL: URL {
        projectURL.appending(path: "auth/v1")
    }

    var restBaseURL: URL {
        projectURL.appending(path: "rest/v1")
    }

    static func load(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> MistiaSyncConfiguration? {
        if let bundleConfig = loadBundleConfiguration(bundle: bundle) {
            return bundleConfig
        }

        guard
            let projectURLRaw = processInfo.environment["MISTIA_SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            let anonKey = processInfo.environment["MISTIA_SUPABASE_ANON_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !projectURLRaw.isEmpty,
            !anonKey.isEmpty,
            let projectURL = URL(string: projectURLRaw)
        else {
            return nil
        }

        return MistiaSyncConfiguration(projectURL: projectURL, anonKey: anonKey)
    }

    private static func loadBundleConfiguration(bundle: Bundle) -> MistiaSyncConfiguration? {
        guard let url = bundle.url(forResource: "MistiaSyncConfig", withExtension: "plist") else {
            return nil
        }

        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let projectURLRaw = (plist["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            let anonKey = (plist["SUPABASE_ANON_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !projectURLRaw.isEmpty,
            !anonKey.isEmpty,
            let projectURL = URL(string: projectURLRaw)
        else {
            return nil
        }

        return MistiaSyncConfiguration(projectURL: projectURL, anonKey: anonKey)
    }
}
