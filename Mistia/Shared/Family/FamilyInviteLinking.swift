import Foundation

struct FamilyInviteRoute: Codable, Equatable, Identifiable {
    let token: String

    var id: String { token }
}

enum FamilyInviteStatus: String, Codable, CaseIterable {
    case pending
    case accepted
    case expired
    case revoked
    case invalid
}

enum FamilyInviteLinking {
    static let webHost = "mistia.app"
    static let webBasePath = "/invite/family"
    static let appScheme = "mistia"
    static let appInviteHost = "family-invite"

    static func webInviteURL(token: String) -> URL {
        URL(string: "https://\(webHost)\(webBasePath)/\(token)")!
    }

    static func appInviteURL(token: String) -> URL {
        URL(string: "\(appScheme)://\(appInviteHost)/\(token)")!
    }

    static func token(from url: URL) -> String? {
        if let token = queryToken(from: url) {
            return token
        }

        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if scheme == appScheme || scheme == "vn.com.quyln.mistia" {
            if host == appInviteHost {
                return normalizedToken(pathComponents.first)
            }

            if host == "invite", pathComponents.first == "family" {
                return normalizedToken(pathComponents.dropFirst().first)
            }

            if host == "family", pathComponents.first == "invite" {
                return normalizedToken(pathComponents.dropFirst().first)
            }
        }

        if scheme == "https",
           host == webHost || host == "www.\(webHost)" {
            guard pathComponents.count >= 3,
                  pathComponents[0] == "invite",
                  pathComponents[1] == "family" else {
                return nil
            }
            return normalizedToken(pathComponents[2])
        }

        return nil
    }

    static func normalizedToken(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func queryToken(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        for key in ["invite", "token", "family_invite"] {
            if let value = components.queryItems?.first(where: { $0.name == key })?.value,
               let token = normalizedToken(value) {
                return token
            }
        }
        return nil
    }
}
