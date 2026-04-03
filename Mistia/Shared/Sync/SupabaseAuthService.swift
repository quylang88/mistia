import Foundation
import GoogleSignIn
import UIKit

enum SupabaseServiceError: LocalizedError {
    case configurationMissing
    case invalidURL
    case invalidResponse
    case serverMessage(String)
    case missingSession
    case missingRefreshToken
    case oauthCancelled
    case googleClientIDMissing
    case googleServerClientIDMissing
    case googleCallbackSchemeMissing(expected: String)
    case googlePresentationContextMissing
    case googleTokensMissing

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "Cloud sync has not been configured yet."
        case .invalidURL:
            return "The cloud service URL is invalid."
        case .invalidResponse:
            return "Received an invalid response from the account service."
        case .serverMessage(let message):
            return message
        case .missingSession:
            return "No active session is available."
        case .missingRefreshToken:
            return "This session can no longer be refreshed."
        case .oauthCancelled:
            return "The Google sign-in flow was cancelled."
        case .googleClientIDMissing:
            return "The app is missing its Google iOS client ID."
        case .googleServerClientIDMissing:
            return "The app is missing its Google web client ID."
        case .googleCallbackSchemeMissing(let expected):
            return "The app is missing the Google callback URL scheme: \(expected)"
        case .googlePresentationContextMissing:
            return "The app couldn't find a screen to present Google sign-in."
        case .googleTokensMissing:
            return "Google sign-in finished without the tokens needed to start syncing."
        }
    }
}

enum SupabaseSignUpOutcome {
    case signedIn(SupabaseAuthSession)
    case emailConfirmationRequired
}

struct SupabaseAuthUser: Codable {
    let id: UUID
    let email: String?
    let userMetadata: SupabaseUserMetadata?
}

struct SupabaseUserMetadata: Codable {
    let displayName: String?
    let fullName: String?
    let name: String?
    let avatarURL: String?
    let picture: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case fullName = "full_name"
        case name
        case avatarURL = "avatar_url"
        case picture
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
    ) async throws -> SupabaseSignUpOutcome {
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
            return .signedIn(session)
        }

        if response.user != nil {
            return .emailConfirmationRequired
        }

        let signedInSession = try await signIn(email: email, password: password)
        return .signedIn(signedInSession)
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

    @MainActor
    func signInWithGoogle() async throws -> SupabaseAuthSession {
        let configuration = try configuration()
        let googleConfiguration = try googleConfiguration()
        let signInResult = try await performNativeGoogleSignIn(
            googleConfiguration: googleConfiguration
        )

        guard let idToken = signInResult.user.idToken?.tokenString else {
            throw SupabaseServiceError.googleTokensMissing
        }

        let response: SupabaseAuthResponse = try await performAuthRequest(
            url: try authTokenURL(configuration: configuration, grantType: "id_token"),
            body: OpenIDConnectGrantBody(
                provider: "google",
                idToken: idToken,
                accessToken: signInResult.user.accessToken.tokenString
            ),
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

        GIDSignIn.sharedInstance.signOut()
        try keychain.removeData(for: "auth-session")
    }

    func requestPasswordReset(email: String) async throws {
        let configuration = try configuration()
        let url = configuration.authBaseURL.appending(path: "recover")
        try await performEmptyAuthRequest(
            url: url,
            body: RecoveryBody(email: email),
            apiKey: configuration.anonKey
        )
    }

    func resendConfirmation(email: String) async throws {
        let configuration = try configuration()
        let url = configuration.authBaseURL.appending(path: "resend")
        try await performEmptyAuthRequest(
            url: url,
            body: ResendBody(email: email, type: "signup"),
            apiKey: configuration.anonKey
        )
    }

    private func refreshSession(_ session: SupabaseAuthSession) async throws -> SupabaseAuthSession {
        guard !session.refreshToken.isEmpty else {
            throw SupabaseServiceError.missingRefreshToken
        }

        let configuration = try configuration()

        let response: SupabaseAuthResponse = try await performAuthRequest(
            url: try authTokenURL(configuration: configuration, grantType: "refresh_token"),
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

    private func googleConfiguration(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) throws -> MistiaGoogleSignInConfiguration {
        guard let clientID = MistiaGoogleSignInConfiguration.clientID(bundle: bundle, processInfo: processInfo) else {
            throw SupabaseServiceError.googleClientIDMissing
        }

        guard let serverClientID = MistiaGoogleSignInConfiguration.serverClientID(bundle: bundle, processInfo: processInfo) else {
            throw SupabaseServiceError.googleServerClientIDMissing
        }

        let googleConfiguration = MistiaGoogleSignInConfiguration(
            clientID: clientID,
            serverClientID: serverClientID,
            callbackScheme: MistiaGoogleSignInConfiguration.reversedClientID(from: clientID)
        )

        guard googleConfiguration.isURLSchemeRegistered(bundle: bundle) else {
            throw SupabaseServiceError.googleCallbackSchemeMissing(expected: googleConfiguration.callbackScheme)
        }

        return googleConfiguration
    }

    private func authTokenURL(
        configuration: MistiaSyncConfiguration,
        grantType: String
    ) throws -> URL {
        guard var components = URLComponents(url: configuration.authBaseURL.appending(path: "token"), resolvingAgainstBaseURL: false) else {
            throw SupabaseServiceError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        guard let url = components.url else { throw SupabaseServiceError.invalidURL }
        return url
    }

    @MainActor
    private func performNativeGoogleSignIn(
        googleConfiguration: MistiaGoogleSignInConfiguration
    ) async throws -> GIDSignInResult {
        let presentingViewController = try googlePresentingViewController()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: googleConfiguration.clientID,
            serverClientID: googleConfiguration.serverClientID
        )

        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { signInResult, error in
                if let error = error as NSError? {
                    if error.domain == kGIDSignInErrorDomain, error.code == GIDSignInError.canceled.rawValue {
                        continuation.resume(throwing: SupabaseServiceError.oauthCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let signInResult else {
                    continuation.resume(throwing: SupabaseServiceError.invalidResponse)
                    return
                }

                continuation.resume(returning: signInResult)
            }
        }
    }

    @MainActor
    private func googlePresentingViewController() throws -> UIViewController {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = windowScenes.flatMap(\.windows)
        guard let rootViewController = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController else {
            throw SupabaseServiceError.googlePresentationContextMissing
        }

        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
            topViewController = presentedViewController
        }

        return topViewController
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
                throw SupabaseServiceError.serverMessage(error.errorDescription ?? error.message ?? "The account request failed.")
            }
            throw SupabaseServiceError.serverMessage("The account request failed with status \(httpResponse.statusCode).")
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func performEmptyAuthRequest<Body: Encodable>(
        url: URL,
        body: Body,
        apiKey: String
    ) async throws {
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
                throw SupabaseServiceError.serverMessage(error.errorDescription ?? error.message ?? "The account request failed.")
            }
            throw SupabaseServiceError.serverMessage("The account request failed with status \(httpResponse.statusCode).")
        }
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

private struct RecoveryBody: Encodable {
    let email: String
}

private struct ResendBody: Encodable {
    let email: String
    let type: String
}

private struct OpenIDConnectGrantBody: Encodable {
    let provider: String
    let idToken: String
    let accessToken: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case accessToken = "access_token"
    }
}

extension SupabaseUserMetadata {
    var resolvedAvatarURL: URL? {
        if let avatarURL, let url = URL(string: avatarURL) {
            return url
        }

        if let picture, let url = URL(string: picture) {
            return url
        }

        return nil
    }
}
