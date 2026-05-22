import Foundation
import SwiftData
import Translation

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

    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && nameEnglish?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && nameJapanese?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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
        session: SupabaseAuthSession?
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
        request.setValue("Bearer \(session?.accessToken ?? configuration.anonKey)", forHTTPHeaderField: "Authorization")
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

struct CategoryNameTranslationResolver {
    private let remoteService: CategoryNameTranslationService

    init(remoteService: CategoryNameTranslationService = CategoryNameTranslationService()) {
        self.remoteService = remoteService
    }

    func translateCategoryName(
        inputName: String,
        sourceLanguage: MistiaAppLanguage,
        fallbackName: CategoryNameTranslations,
        session: SupabaseAuthSession?
    ) async -> CategoryNameTranslations? {
        if let local = await translateOnDevice(inputName: inputName, sourceLanguage: sourceLanguage, fallbackName: fallbackName),
           local.isComplete {
            return local
        }

        do {
            let remote = try await remoteService.translateCategoryName(
                inputName: inputName,
                sourceLanguage: sourceLanguage,
                session: session
            )
            return CategoryNameTranslations(
                name: remote.name.nilIfBlank ?? fallbackName.name,
                nameEnglish: remote.nameEnglish ?? fallbackName.nameEnglish,
                nameJapanese: remote.nameJapanese ?? fallbackName.nameJapanese
            )
        } catch {
            return nil
        }
    }

    private func translateOnDevice(
        inputName: String,
        sourceLanguage: MistiaAppLanguage,
        fallbackName: CategoryNameTranslations
    ) async -> CategoryNameTranslations? {
        var name = fallbackName.name
        var nameEnglish = fallbackName.nameEnglish
        var nameJapanese = fallbackName.nameJapanese

        if sourceLanguage != .vietnamese,
           let translated = await translateInstalledLanguagePack(
            inputName,
            from: sourceLanguage,
            to: .vietnamese
           ) {
            name = translated
        }

        if sourceLanguage != .english,
           let translated = await translateInstalledLanguagePack(
            inputName,
            from: sourceLanguage,
            to: .english
           ) {
            nameEnglish = translated
        }

        if sourceLanguage != .japanese,
           let translated = await translateInstalledLanguagePack(
            inputName,
            from: sourceLanguage,
            to: .japanese
           ) {
            nameJapanese = translated
        }

        let result = CategoryNameTranslations(name: name, nameEnglish: nameEnglish, nameJapanese: nameJapanese)
        return result == fallbackName ? nil : result
    }

    private func translateInstalledLanguagePack(
        _ inputName: String,
        from sourceLanguage: MistiaAppLanguage,
        to targetLanguage: MistiaAppLanguage
    ) async -> String? {
        guard sourceLanguage != targetLanguage else { return inputName }
        let source = sourceLanguage.translationLocaleLanguage
        let target = targetLanguage.translationLocaleLanguage
        let availability = LanguageAvailability()
        guard await availability.status(from: source, to: target) == .installed else {
            return nil
        }

        do {
            let session = TranslationSession(installedSource: source, target: target)
            let response = try await session.translate(inputName)
            return response.targetText.nilIfBlank
        } catch {
            return nil
        }
    }
}

@MainActor
enum CategoryNameTranslationMaintenance {
    private static let cooldownInterval: TimeInterval = 5 * 60
    private static let deferredStartNanoseconds: UInt64 = 750_000_000
    private static let batchSize = 16
    private static var inFlightTask: Task<Void, Never>?
    private static var lastCompletedAt: Date?

    static func run(
        modelContext: ModelContext,
        sessionStore: SessionStore,
        limit: Int = 200
    ) async {
        let now = Date()
        if let inFlightTask {
            debugLog("coalesced with in-flight run")
            await inFlightTask.value
            return
        }
        if let lastCompletedAt,
           now.timeIntervalSince(lastCompletedAt) < cooldownInterval {
            debugLog("skipped by cooldown")
            return
        }

        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: deferredStartNanoseconds)
            await runImmediately(
                modelContext: modelContext,
                sessionStore: sessionStore,
                limit: limit
            )
        }
        inFlightTask = task
        await task.value
        inFlightTask = nil
        lastCompletedAt = Date()
    }

    private static func runImmediately(
        modelContext: ModelContext,
        sessionStore: SessionStore,
        limit: Int
    ) async {
        let startTime = Date()
        let categories = fetchCandidateCategories(modelContext: modelContext, limit: limit)
        let candidates = categories.filter { $0.needsCategoryNameTranslationRetry }
        guard !candidates.isEmpty else { return }

        let resolver = CategoryNameTranslationResolver()
        let session = try? await sessionStore.refreshedSession()
        var updatedCount = 0
        for category in candidates.prefix(batchSize) {
            guard let source = category.categoryNameTranslationSource else { continue }
            let fallbackName = CategoryNameTranslations.fallback(
                inputName: source.name,
                sourceLanguage: source.language,
                existingCategory: category
            )
            guard let translatedName = await resolver.translateCategoryName(
                inputName: source.name,
                sourceLanguage: source.language,
                fallbackName: fallbackName,
                session: session
            ), translatedName != fallbackName else {
                continue
            }

            let now = Date()
            category.name = translatedName.name
            category.nameEnglish = translatedName.nameEnglish
            category.nameJapanese = translatedName.nameJapanese
            category.pendingTranslationSourceName = nil
            category.pendingTranslationSourceLanguageRawValue = nil
            category.updatedAt = now

            do {
                try modelContext.save()
                sessionStore.recordUpsert(entity: .category, recordID: category.id, modifiedAt: now)
                updatedCount += 1
            } catch {
                modelContext.rollback()
            }
        }
        debugLog("finished candidates=\(candidates.count) processed=\(min(candidates.count, batchSize)) updated=\(updatedCount) elapsed=\(Date().timeIntervalSince(startTime))")
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[CategoryNameTranslationMaintenance] \(message)")
        #endif
    }

    private static func fetchCandidateCategories(
        modelContext: ModelContext,
        limit: Int
    ) -> [TransactionCategory] {
        var pendingDescriptor = FetchDescriptor<TransactionCategory>(
            predicate: #Predicate { category in
                category.deletedAt == nil
                    && category.isArchived == false
                    && category.isSystem == false
                    && category.pendingTranslationSourceName != nil
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        pendingDescriptor.fetchLimit = limit

        var missingEnglishDescriptor = FetchDescriptor<TransactionCategory>(
            predicate: #Predicate { category in
                category.deletedAt == nil
                    && category.isArchived == false
                    && category.isSystem == false
                    && category.nameEnglish == nil
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        missingEnglishDescriptor.fetchLimit = limit

        var blankEnglishDescriptor = FetchDescriptor<TransactionCategory>(
            predicate: #Predicate { category in
                category.deletedAt == nil
                    && category.isArchived == false
                    && category.isSystem == false
                    && category.nameEnglish == ""
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        blankEnglishDescriptor.fetchLimit = limit

        var missingJapaneseDescriptor = FetchDescriptor<TransactionCategory>(
            predicate: #Predicate { category in
                category.deletedAt == nil
                    && category.isArchived == false
                    && category.isSystem == false
                    && category.nameJapanese == nil
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        missingJapaneseDescriptor.fetchLimit = limit

        var blankJapaneseDescriptor = FetchDescriptor<TransactionCategory>(
            predicate: #Predicate { category in
                category.deletedAt == nil
                    && category.isArchived == false
                    && category.isSystem == false
                    && category.nameJapanese == ""
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        blankJapaneseDescriptor.fetchLimit = limit

        let fetched = ((try? modelContext.fetch(pendingDescriptor)) ?? [])
            + ((try? modelContext.fetch(missingEnglishDescriptor)) ?? [])
            + ((try? modelContext.fetch(blankEnglishDescriptor)) ?? [])
            + ((try? modelContext.fetch(missingJapaneseDescriptor)) ?? [])
            + ((try? modelContext.fetch(blankJapaneseDescriptor)) ?? [])
        var categoriesByID: [UUID: TransactionCategory] = [:]
        for category in fetched {
            categoriesByID[category.id] = category
        }
        return categoriesByID.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
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

private struct CategoryNameTranslationSource {
    let name: String
    let language: MistiaAppLanguage
}

private extension TransactionCategory {
    var needsCategoryNameTranslationRetry: Bool {
        if pendingTranslationSourceName?.nilIfBlank != nil,
           pendingTranslationSourceLanguageRawValue.flatMap(MistiaAppLanguage.init(rawValue:)) != nil {
            return true
        }
        return nameEnglish?.nilIfBlank == nil || nameJapanese?.nilIfBlank == nil || name.nilIfBlank == nil
    }

    var categoryNameTranslationSource: CategoryNameTranslationSource? {
        if let pendingName = pendingTranslationSourceName?.nilIfBlank,
           let languageRawValue = pendingTranslationSourceLanguageRawValue,
           let language = MistiaAppLanguage(rawValue: languageRawValue) {
            return CategoryNameTranslationSource(name: pendingName, language: language)
        }

        if let japaneseName = nameJapanese?.nilIfBlank,
           name.nilIfBlank == japaneseName || japaneseName.containsJapaneseCharacters {
            return CategoryNameTranslationSource(name: japaneseName, language: .japanese)
        }

        if let englishName = nameEnglish?.nilIfBlank,
           name.nilIfBlank == englishName,
           nameJapanese?.nilIfBlank == nil {
            return CategoryNameTranslationSource(name: englishName, language: .english)
        }

        guard let vietnameseName = name.nilIfBlank else { return nil }
        return CategoryNameTranslationSource(name: vietnameseName, language: .vietnamese)
    }
}

private extension MistiaAppLanguage {
    var translationLocaleLanguage: Locale.Language {
        switch self {
        case .vietnamese:
            Locale.Language(identifier: "vi")
        case .english:
            Locale.Language(identifier: "en")
        case .japanese:
            Locale.Language(identifier: "ja")
        }
    }
}

private extension String {
    var containsJapaneseCharacters: Bool {
        range(of: "[ぁ-んァ-ン一-龯]", options: .regularExpression) != nil
    }
}
