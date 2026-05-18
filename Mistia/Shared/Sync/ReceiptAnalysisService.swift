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
            mistiaLocalized(vi: "Bạn cần đăng nhập để phân tích bill.", en: "Sign in to analyze receipts.", ja: "レシート解析にはサインインが必要です。")
        case 413:
            mistiaLocalized(vi: "Ảnh bill quá lớn. Hãy chọn ảnh rõ hơn nhưng nhẹ hơn.", en: "The receipt image is too large. Choose a clearer, smaller image.", ja: "レシート画像が大きすぎます。より軽い画像を選択してください。")
        case 429:
            mistiaLocalized(vi: "Bạn đã đạt giới hạn quét bill hôm nay. Vui lòng thử lại sau thời điểm reset ngày.", en: "You've reached today's receipt scan limit. Try again after the daily reset.", ja: "本日のレシート読み取り上限に達しました。日次リセット後にもう一度お試しください。")
        default:
            mistiaLocalized(vi: "Không thể phân tích bill lúc này.", en: "Couldn't analyze this receipt right now.", ja: "現在レシートを解析できません。")
        }
    }

    static func limitReachedMessage(for quota: ReceiptAnalysisQuota) -> String {
        let retryText: String
        if let retryAfter = quota.retryAfter {
            retryText = Self.retryDateFormatter.string(from: retryAfter)
        } else {
            retryText = mistiaLocalized(vi: "lần reset ngày tiếp theo", en: "the next daily reset", ja: "次の日次リセット")
        }

        return mistiaLocalized(
            vi: "Bạn đã đạt giới hạn quét bill hôm nay. Vui lòng thử lại sau \(retryText).",
            en: "You've reached today's receipt scan limit. Try again after \(retryText).",
            ja: "本日のレシート読み取り上限に達しました。\(retryText) 以降にもう一度お試しください。"
        )
    }

    private static let retryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
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
