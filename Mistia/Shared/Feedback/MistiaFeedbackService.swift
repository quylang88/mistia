import Foundation

public protocol MistiaFeedbackServicing: Sendable {
    func submitFeedback(_ submission: MistiaFeedbackSubmission) async throws
}

public final class MistiaFeedbackService: MistiaFeedbackServicing, Sendable {
    public static let shared = MistiaFeedbackService()
    
    private init() {}

    public func submitFeedback(_ submission: MistiaFeedbackSubmission) async throws {
        guard let configuration = MistiaSyncConfiguration.load() else {
            throw SupabaseServiceError.configurationMissing
        }

        struct FeedbackInsertDTO: Encodable {
            let user_id: UUID?
            let category: String
            let rating: Int?
            let content: String
            let device_info: [String: String]?
        }

        let session = try? SupabaseAuthService().loadPersistedSession()

        let dto = FeedbackInsertDTO(
            user_id: session?.user.id,
            category: submission.category.rawValue,
            rating: submission.rating,
            content: submission.content,
            device_info: submission.deviceInfo
        )

        let url = configuration.restBaseURL.appending(path: "user_feedbacks")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")

        if let session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(dto)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let rawBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseServiceError.serverMessage("[POST user_feedbacks] HTTP \(httpResponse.statusCode): \(rawBody)")
        }
    }
}
