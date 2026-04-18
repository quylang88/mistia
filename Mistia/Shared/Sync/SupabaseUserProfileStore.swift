import Foundation

protocol UserProfileRemoteStoring {
    func fetchProfile(session: SupabaseAuthSession) async throws -> RemoteUserProfile?
    func upsertProfile(
        displayName: String,
        avatarURL: URL?,
        birthday: Date?,
        session: SupabaseAuthSession
    ) async throws -> RemoteUserProfile
    func uploadAvatarImageData(
        _ data: Data,
        session: SupabaseAuthSession
    ) async throws -> URL
}

struct RemoteUserProfile: Decodable {
    let userID: UUID
    let displayName: String
    let avatarURL: URL?
    let birthday: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case birthday
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        userID: UUID,
        displayName: String,
        avatarURL: URL?,
        birthday: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.birthday = birthday
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""

        if let avatarURLRaw = try container.decodeIfPresent(String.self, forKey: .avatarURL),
           !avatarURLRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            avatarURL = URL(string: avatarURLRaw)
        } else {
            avatarURL = nil
        }

        if let birthdayRaw = try container.decodeIfPresent(String.self, forKey: .birthday),
           !birthdayRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            birthday = Self.birthdayFormatter.date(from: birthdayRaw)
        } else {
            birthday = nil
        }

        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    private static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct SupabaseUserProfileStore: UserProfileRemoteStoring {
    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let decoder = JSONDecoder.mistiaRemoteAPIDecoder
    private let encoder = JSONEncoder()

    init(configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() }) {
        self.configurationProvider = configurationProvider
    }

    func fetchProfile(session: SupabaseAuthSession) async throws -> RemoteUserProfile? {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: "user_profiles"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        let rows: [RemoteUserProfile] = try await performRequest(
            request: authorizedJSONRequest(url: url, session: session)
        )
        return rows.first
    }

    func upsertProfile(
        displayName: String,
        avatarURL: URL?,
        birthday: Date?,
        session: SupabaseAuthSession
    ) async throws -> RemoteUserProfile {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: "user_profiles"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "on_conflict", value: "user_id")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        let payload = UserProfileUpsertPayload(
            userID: session.user.id,
            displayName: normalizeDisplayName(displayName, fallbackEmail: session.user.email),
            avatarURL: avatarURL,
            birthday: birthday
        )

        var request = authorizedJSONRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode([payload])

        let rows: [RemoteUserProfile] = try await performRequest(request: request)
        guard let profile = rows.first else {
            throw SupabaseServiceError.invalidResponse
        }
        return profile
    }

    func uploadAvatarImageData(
        _ data: Data,
        session: SupabaseAuthSession
    ) async throws -> URL {
        let configuration = try configuration()
        let userID = session.user.id.uuidString.lowercased()
        let uploadURL = configuration.projectURL
            .appending(path: "storage/v1/object/profile-avatars")
            .appending(path: userID)
            .appending(path: "avatar.jpg")

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw requestErrorMessage(
                request: request,
                statusCode: httpResponse.statusCode,
                data: responseData
            )
        }

        var components = URLComponents(
            url: configuration.projectURL
                .appending(path: "storage/v1/object/public/profile-avatars")
                .appending(path: userID)
                .appending(path: "avatar.jpg"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
        ]

        guard let publicURL = components?.url else {
            throw SupabaseServiceError.invalidURL
        }

        return publicURL
    }

    private func configuration() throws -> MistiaSyncConfiguration {
        guard let configuration = configurationProvider() else {
            throw SupabaseServiceError.configurationMissing
        }
        return configuration
    }

    private func authorizedJSONRequest(
        url: URL,
        session: SupabaseAuthSession
    ) -> URLRequest {
        let apiKey = configurationProvider()?.anonKey ?? ""
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performRequest<Response: Decodable>(
        request: URLRequest
    ) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw requestErrorMessage(
                request: request,
                statusCode: httpResponse.statusCode,
                data: data
            )
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func requestErrorMessage(
        request: URLRequest,
        statusCode: Int,
        data: Data
    ) -> SupabaseServiceError {
        let operation = request.httpMethod ?? "REQUEST"
        let target = request.url?.lastPathComponent ?? "user_profiles"

        let responseMessage: String? = {
            if let error = try? decoder.decode(SupabaseServiceErrorResponse.self, from: data) {
                return error.errorDescription ?? error.message
            }

            let rawBody = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rawBody?.isEmpty == false ? rawBody : nil
        }()

        let message = responseMessage ?? "The user profile request failed."
        return .serverMessage("[\(operation) \(target)] HTTP \(statusCode): \(message)")
    }

    private func normalizeDisplayName(
        _ displayName: String,
        fallbackEmail: String?
    ) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        if let fallbackEmail, !fallbackEmail.isEmpty {
            let localPart = fallbackEmail.components(separatedBy: "@").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let localPart, !localPart.isEmpty {
                return localPart
            }
        }

        return "Mistia"
    }
}

private struct UserProfileUpsertPayload: Encodable {
    let userID: UUID
    let displayName: String
    let avatarURL: String?
    let birthday: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case birthday
    }

    init(
        userID: UUID,
        displayName: String,
        avatarURL: URL?,
        birthday: Date?
    ) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL?.absoluteString
        self.birthday = birthday.map(Self.birthdayFormatter.string(from:))
    }

    private static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
