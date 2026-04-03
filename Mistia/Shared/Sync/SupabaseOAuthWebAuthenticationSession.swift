import AuthenticationServices
import UIKit

@MainActor
final class SupabaseOAuthWebAuthenticationSession: NSObject {
    private var session: ASWebAuthenticationSession?

    func authenticate(
        url: URL,
        callbackScheme: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                self.session = nil

                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    continuation.resume(throwing: SupabaseServiceError.oauthCancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: SupabaseServiceError.oauthCallbackMissing)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            guard session.start() else {
                self.session = nil
                continuation.resume(throwing: SupabaseServiceError.oauthSessionStartFailed)
                return
            }
        }
    }
}

extension SupabaseOAuthWebAuthenticationSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let keyWindow = windowScenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }

        guard let windowScene = windowScenes.first else {
            preconditionFailure("No UIWindowScene available for Google sign-in.")
        }

        return ASPresentationAnchor(windowScene: windowScene)
    }
}
