import Foundation

enum SupabaseServiceError: LocalizedError {
    case configurationMissing
    case invalidURL
    case invalidResponse
    case serverMessage(String)
    case missingSession
    case missingRefreshToken
    case emailConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "Supabase sync has not been configured yet."
        case .invalidURL:
            return "The Supabase URL is invalid."
        case .invalidResponse:
            return "Received an invalid response from Supabase."
        case .serverMessage(let message):
            return message
        case .missingSession:
            return "No active session is available."
        case .missingRefreshToken:
            return "This session can no longer be refreshed."
        case .emailConfirmationRequired:
            return "Check your email to confirm the account before signing in."
        }
    }
}

struct SupabaseAuthUser: Codable {
    let id: UUID
    let email: String?
    let userMetadata: SupabaseUserMetadata?
}

struct SupabaseUserMetadata: Codable {
    let displayName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case name
    }
}

struct SupabaseAuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: Date?
    let user: SupabaseAuthUser

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(60)
    }
}

private struct SupabaseAuthResponse: Codable {
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let expiresAt: TimeInterval?
    let user: SupabaseAuthUser?

    func resolvedSession() -> SupabaseAuthSession? {
        guard
            let accessToken,
            let refreshToken,
            let tokenType,
            let user
        else {
            return nil
        }

        let expiration = expiresAt.map(Date.init(timeIntervalSince1970:))
            ?? expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }

        return SupabaseAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresAt: expiration,
            user: user
        )
    }
}

struct SupabaseServiceErrorResponse: Codable {
    let message: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
    }
}

struct SupabaseAuthService {
    private let keychain: KeychainStore
    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let decoder = JSONDecoder.mistiaSyncDecoder
    private let encoder = JSONEncoder.mistiaSyncEncoder

    init(
        keychain: KeychainStore = KeychainStore(),
        configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() }
    ) {
        self.keychain = keychain
        self.configurationProvider = configurationProvider
    }

    func restoreSession() async throws -> SupabaseAuthSession? {
        guard let data = try keychain.data(for: "auth-session") else {
            return nil
        }

        let session = try decoder.decode(SupabaseAuthSession.self, from: data)
        return try await refreshSessionIfNeeded(session)
    }

    func signUp(
        email: String,
        password: String,
        displayName: String
    ) async throws -> SupabaseAuthSession {
        let configuration = try configuration()
        let url = configuration.authBaseURL.appending(path: "signup")
        let body = SignupBody(
            email: email,
            password: password,
            data: SignupMetadata(displayName: displayName)
        )
        let response: SupabaseAuthResponse = try await performAuthRequest(
            url: url,
            body: body,
            apiKey: configuration.anonKey
        )

        if let session = response.resolvedSession() {
            try persist(session: session)
            return session
        }

        if response.user != nil {
            throw SupabaseServiceError.emailConfirmationRequired
        }

        let signedInSession = try await signIn(email: email, password: password)
        return signedInSession
    }

    func signIn(
        email: String,
        password: String
    ) async throws -> SupabaseAuthSession {
        let configuration = try configuration()
        guard var components = URLComponents(url: configuration.authBaseURL.appending(path: "token"), resolvingAgainstBaseURL: false) else {
            throw SupabaseServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "password")
        ]
        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        let response: SupabaseAuthResponse = try await performAuthRequest(
            url: url,
            body: PasswordGrantBody(email: email, password: password),
            apiKey: configuration.anonKey
        )

        guard let session = response.resolvedSession() else {
            throw SupabaseServiceError.invalidResponse
        }

        try persist(session: session)
        return session
    }

    func refreshSessionIfNeeded(_ session: SupabaseAuthSession) async throws -> SupabaseAuthSession {
        guard session.isExpired else {
            return session
        }

        return try await refreshSession(session)
    }

    func signOut(session: SupabaseAuthSession?) async throws {
        if let session, let configuration = configurationProvider() {
            let url = configuration.authBaseURL.appending(path: "logout")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }

        try keychain.removeData(for: "auth-session")
    }

    private func refreshSession(_ session: SupabaseAuthSession) async throws -> SupabaseAuthSession {
        guard !session.refreshToken.isEmpty else {
            throw SupabaseServiceError.missingRefreshToken
        }

        let configuration = try configuration()
        guard var components = URLComponents(url: configuration.authBaseURL.appending(path: "token"), resolvingAgainstBaseURL: false) else {
            throw SupabaseServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        let response: SupabaseAuthResponse = try await performAuthRequest(
            url: url,
            body: RefreshGrantBody(refreshToken: session.refreshToken),
            apiKey: configuration.anonKey
        )

        guard let refreshedSession = response.resolvedSession() else {
            throw SupabaseServiceError.invalidResponse
        }

        try persist(session: refreshedSession)
        return refreshedSession
    }

    private func configuration() throws -> MistiaSyncConfiguration {
        guard let configuration = configurationProvider() else {
            throw SupabaseServiceError.configurationMissing
        }
        return configuration
    }

    private func persist(session: SupabaseAuthSession) throws {
        let data = try encoder.encode(session)
        try keychain.set(data, for: "auth-session")
    }

    private func performAuthRequest<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body,
        apiKey: String
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? decoder.decode(SupabaseServiceErrorResponse.self, from: data) {
                throw SupabaseServiceError.serverMessage(error.errorDescription ?? error.message ?? "Supabase auth request failed.")
            }
            throw SupabaseServiceError.serverMessage("Supabase auth request failed with status \(httpResponse.statusCode).")
        }

        return try decoder.decode(Response.self, from: data)
    }
}

private struct SignupBody: Encodable {
    let email: String
    let password: String
    let data: SignupMetadata
}

private struct SignupMetadata: Encodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct PasswordGrantBody: Encodable {
    let email: String
    let password: String
}

private struct RefreshGrantBody: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}
