import Foundation

struct CategoryNameTranslations: Equatable {
    let name: String
    let nameEnglish: String?
    let nameJapanese: String?

    static func fallback(
        inputName: String,
        sourceLanguage: MistiaAppLanguage,
        existingCategory: TransactionCategory? = nil
    ) -> CategoryNameTranslations {
        let existingName = existingCategory?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingEnglish = existingCategory?.nameEnglish?.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingJapanese = existingCategory?.nameJapanese?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch sourceLanguage {
        case .vietnamese:
            return CategoryNameTranslations(
                name: inputName,
                nameEnglish: existingEnglish?.isEmpty == false ? existingEnglish : nil,
                nameJapanese: existingJapanese?.isEmpty == false ? existingJapanese : nil
            )
        case .english:
            return CategoryNameTranslations(
                name: existingName?.isEmpty == false ? existingName! : inputName,
                nameEnglish: inputName,
                nameJapanese: existingJapanese?.isEmpty == false ? existingJapanese : nil
            )
        case .japanese:
            return CategoryNameTranslations(
                name: existingName?.isEmpty == false ? existingName! : inputName,
                nameEnglish: existingEnglish?.isEmpty == false ? existingEnglish : nil,
                nameJapanese: inputName
            )
        }
    }
}

struct CategoryNameTranslationService {
    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let encoder = JSONEncoder.mistiaRemoteAPIEncoder
    private let decoder = JSONDecoder.mistiaRemoteAPIDecoder

    init(configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() }) {
        self.configurationProvider = configurationProvider
    }

    func translateCategoryName(
        inputName: String,
        sourceLanguage: MistiaAppLanguage,
        session: SupabaseAuthSession
    ) async throws -> CategoryNameTranslations {
        guard let configuration = configurationProvider() else {
            throw SupabaseServiceError.configurationMissing
        }

        let url = configuration.functionsBaseURL.appending(path: "translate-category-name")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(CategoryNameTranslationRequest(
            name: inputName,
            sourceLanguage: sourceLanguage.rawValue
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? decoder.decode(CategoryNameTranslationErrorResponse.self, from: data) {
                throw SupabaseServiceError.serverMessage(error.message ?? "Category translation failed.")
            }
            throw SupabaseServiceError.serverMessage("Category translation failed.")
        }

        let result = try decoder.decode(CategoryNameTranslationResponse.self, from: data)
        return CategoryNameTranslations(
            name: result.nameVietnamese.trimmingCharacters(in: .whitespacesAndNewlines),
            nameEnglish: result.nameEnglish.nilIfBlank,
            nameJapanese: result.nameJapanese.nilIfBlank
        )
    }
}

private struct CategoryNameTranslationRequest: Codable {
    let name: String
    let sourceLanguage: String

    enum CodingKeys: String, CodingKey {
        case name
        case sourceLanguage = "source_language"
    }
}

private struct CategoryNameTranslationResponse: Codable {
    let nameVietnamese: String
    let nameEnglish: String
    let nameJapanese: String

    enum CodingKeys: String, CodingKey {
        case nameVietnamese = "name_vietnamese"
        case nameEnglish = "name_english"
        case nameJapanese = "name_japanese"
    }
}

private struct CategoryNameTranslationErrorResponse: Codable {
    let message: String?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
