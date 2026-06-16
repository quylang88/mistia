import Foundation

enum ReceiptAnalysisServiceError: LocalizedError {
    case dailyLimitReached(ReceiptAnalysisQuota)

    var errorDescription: String? {
        switch self {
        case .dailyLimitReached(let quota):
            ReceiptAnalysisService.limitReachedMessage(for: quota)
        }
    }
}

struct ReceiptAnalysisService {
    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let encoder = JSONEncoder.mistiaRemoteAPIEncoder
    private let decoder = JSONDecoder.mistiaRemoteAPIDecoder

    init(configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() }) {
        self.configurationProvider = configurationProvider
    }

    func analyzeReceipt(
        payload: ReceiptAnalysisRequestPayload,
        session: SupabaseAuthSession
    ) async throws -> ReceiptAnalysisResult {
        guard let configuration = configurationProvider() else {
            throw SupabaseServiceError.configurationMissing
        }

        let url = configuration.functionsBaseURL.appending(path: "analyze-receipt")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429,
               let error = try? decoder.decode(ReceiptAnalysisErrorResponse.self, from: data),
               let quota = error.quota {
                throw ReceiptAnalysisServiceError.dailyLimitReached(quota)
            }

            if let error = try? decoder.decode(ReceiptAnalysisErrorResponse.self, from: data) {
                throw SupabaseServiceError.serverMessage(
                    error.errorDescription ?? error.message ?? receiptAnalysisFallbackErrorMessage(statusCode: httpResponse.statusCode)
                )
            }

            let rawBody = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SupabaseServiceError.serverMessage(
                rawBody?.isEmpty == false ? rawBody! : receiptAnalysisFallbackErrorMessage(statusCode: httpResponse.statusCode)
            )
        }

        return try decoder.decode(ReceiptAnalysisResult.self, from: data)
    }

    private func receiptAnalysisFallbackErrorMessage(statusCode: Int) -> String {
        switch statusCode {
        case 401:
            L10n.shared.sync.receiptanalysis.signInToAnalyzeReceipts
        case 413:
            L10n.shared.sync.receiptanalysis.theReceiptImageIsTooLargeChoose
        case 429:
            L10n.shared.sync.receiptanalysis.youVeReachedTodaySReceiptScan2
        default:
            L10n.shared.sync.receiptanalysis.couldnTAnalyzeThisReceiptRightNow
        }
    }

    static func limitReachedMessage(
        for quota: ReceiptAnalysisQuota,
        language: MistiaAppLanguage = .current
    ) -> String {
        let retryText: String
        if let retryAfter = quota.retryAfter {
            retryText = MistiaDateFormatting.dateTimeString(for: retryAfter, language: language)
        } else {
            retryText = L10n.shared.sync.receiptanalysis.theNextDailyReset(language: language)
        }

        return L10n.shared.sync.receiptanalysis.youVeReachedTodaySReceiptScan(
            String(describing: retryText),
            language: language
        )
    }
}

private struct ReceiptAnalysisErrorResponse: Codable {
    let message: String?
    let errorDescription: String?
    let quota: ReceiptAnalysisQuota?

    enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
        case quota
    }
}
