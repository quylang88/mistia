import Observation

struct SessionSummary: Equatable {
    let displayName: String
    let email: String

    var initials: String {
        let components = displayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if components.isEmpty {
            return "MI"
        }

        return components.joined()
    }
}

@Observable
final class SessionStore {
    var summary: SessionSummary?
}
