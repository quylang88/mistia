import Foundation

struct BillItemAnalysisService {
    private static let requestTimeout: TimeInterval = 170
    private static let resourceTimeout: TimeInterval = 180
    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let urlSession: URLSession
    private let encoder = JSONEncoder.mistiaRemoteAPIEncoder
    private let decoder = JSONDecoder.mistiaRemoteAPIDecoder

    init(
        configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() },
        urlSession: URLSession = Self.urlSession
    ) {
        self.configurationProvider = configurationProvider
        self.urlSession = urlSession
    }

    func analyzeBillItems(
        payload: BillItemAnalysisRequestPayload,
        session: SupabaseAuthSession
    ) async throws -> BillItemAnalysisResult {
        guard let configuration = configurationProvider() else {
            throw SupabaseServiceError.configurationMissing
        }

        let url = configuration.functionsBaseURL.appending(path: "analyze-bill-items")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Self.requestTimeout
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429,
               let error = try? decoder.decode(BillItemAnalysisErrorResponse.self, from: data),
               let quota = error.quota {
                throw ReceiptAnalysisServiceError.dailyLimitReached(quota)
            }

            throw SupabaseServiceError.serverMessage(
                fallbackErrorMessage(statusCode: httpResponse.statusCode)
            )
        }

        return try decoder.decode(BillItemAnalysisResult.self, from: data)
    }

    private func fallbackErrorMessage(statusCode: Int) -> String {
        switch statusCode {
        case 401:
            L10n.shared.sync.receiptanalysis.signInToAnalyzeReceipts
        case 413:
            L10n.shared.sync.receiptanalysis.theReceiptImageIsTooLargeChoose
        case 429:
            L10n.shared.sync.receiptanalysis.youVeReachedTodaySReceiptScan2
        case 502, 504:
            L10n.shared.sync.receiptanalysis.receiptAITookTooLongTryAgain
        default:
            L10n.shared.sync.receiptanalysis.couldnTAnalyzeThisReceiptRightNow
        }
    }
}

private struct BillItemAnalysisErrorResponse: Codable {
    let message: String?
    let errorDescription: String?
    let quota: ReceiptAnalysisQuota?

    enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
        case quota
    }
}
