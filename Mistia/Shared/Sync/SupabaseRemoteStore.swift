import Foundation

struct SupabaseRemoteStore {
    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let decoder = JSONDecoder.mistiaSyncDecoder
    private let encoder = JSONEncoder.mistiaSyncEncoder

    init(configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() }) {
        self.configurationProvider = configurationProvider
    }

    func fetchSnapshot(session: SupabaseAuthSession) async throws -> MistiaRemoteSnapshot {
        async let wallets: [RemoteLedgerWallet] = fetchRows(entity: .wallet, session: session)
        async let profiles: [RemoteCreditCardProfile] = fetchRows(entity: .creditCardProfile, session: session)
        async let categories: [RemoteTransactionCategory] = fetchRows(entity: .category, session: session)
        async let transactions: [RemoteLedgerTransaction] = fetchRows(entity: .transaction, session: session)
        async let budgetPlans: [RemoteBudgetPlan] = fetchRows(entity: .budgetPlan, session: session)
        async let savingsGoals: [RemoteSavingsGoal] = fetchRows(entity: .savingsGoal, session: session)
        async let recurringBillPlans: [RemoteRecurringBillPlan] = fetchRows(entity: .recurringBillPlan, session: session)
        async let installmentPlans: [RemoteInstallmentPlan] = fetchRows(entity: .installmentPlan, session: session)
        async let dueOccurrences: [RemoteDueOccurrenceRecord] = fetchRows(entity: .dueOccurrenceRecord, session: session)

        return try await MistiaRemoteSnapshot(
            wallets: wallets,
            creditCardProfiles: profiles,
            categories: categories,
            transactions: transactions,
            budgetPlans: budgetPlans,
            savingsGoals: savingsGoals,
            recurringBillPlans: recurringBillPlans,
            installmentPlans: installmentPlans,
            dueOccurrences: dueOccurrences
        )
    }

    func fetchVersion(
        for entity: MistiaSyncEntity,
        recordID: UUID,
        session: SupabaseAuthSession
    ) async throws -> RemoteRowVersion? {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: entity.tableName),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "id,updated_at,deleted_at"),
            URLQueryItem(name: "id", value: "eq.\(recordID.uuidString.lowercased())"),
            URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        let rows: [RemoteRowVersion] = try await performRequest(
            request: authorizedRequest(url: url, session: session)
        )
        return rows.first
    }

    func upsert(
        _ record: MistiaSyncUploadRecord,
        session: SupabaseAuthSession
    ) async throws {
        switch record {
        case .wallet(let row):
            try await upsertRows([row], entity: .wallet, session: session)
        case .creditCardProfile(let row):
            try await upsertRows([row], entity: .creditCardProfile, session: session)
        case .category(let row):
            try await upsertRows([row], entity: .category, session: session)
        case .transaction(let row):
            try await upsertRows([row], entity: .transaction, session: session)
        case .budgetPlan(let row):
            try await upsertRows([row], entity: .budgetPlan, session: session)
        case .savingsGoal(let row):
            try await upsertRows([row], entity: .savingsGoal, session: session)
        case .recurringBillPlan(let row):
            try await upsertRows([row], entity: .recurringBillPlan, session: session)
        case .installmentPlan(let row):
            try await upsertRows([row], entity: .installmentPlan, session: session)
        case .dueOccurrence(let row):
            try await upsertRows([row], entity: .dueOccurrenceRecord, session: session)
        }
    }

    func uploadSeed(
        snapshot: MistiaRemoteSnapshot,
        session: SupabaseAuthSession
    ) async throws {
        try await upsertRows(snapshot.wallets, entity: .wallet, session: session)
        try await upsertRows(snapshot.categories, entity: .category, session: session)
        try await upsertRows(snapshot.creditCardProfiles, entity: .creditCardProfile, session: session)
        try await upsertRows(snapshot.transactions, entity: .transaction, session: session)
        try await upsertRows(snapshot.budgetPlans, entity: .budgetPlan, session: session)
        try await upsertRows(snapshot.savingsGoals, entity: .savingsGoal, session: session)
        try await upsertRows(snapshot.recurringBillPlans, entity: .recurringBillPlan, session: session)
        try await upsertRows(snapshot.installmentPlans, entity: .installmentPlan, session: session)
        try await upsertRows(snapshot.dueOccurrences, entity: .dueOccurrenceRecord, session: session)
    }

    func softDelete(
        entity: MistiaSyncEntity,
        recordID: UUID,
        modifiedAt: Date,
        session: SupabaseAuthSession
    ) async throws {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: entity.tableName),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(recordID.uuidString.lowercased())"),
            URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        let payload = DeletePatch(
            updatedAt: modifiedAt,
            deletedAt: modifiedAt
        )

        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "PATCH"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(payload)

        _ = try await performEmptyRequest(request: request)
    }

    private func fetchRows<Row: MistiaRemoteRow>(
        entity: MistiaSyncEntity,
        session: SupabaseAuthSession
    ) async throws -> [Row] {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: entity.tableName),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "updated_at.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        return try await performRequest(request: authorizedRequest(url: url, session: session))
    }

    private func upsertRows<Row: MistiaRemoteRow>(
        _ rows: [Row],
        entity: MistiaSyncEntity,
        session: SupabaseAuthSession
    ) async throws {
        guard !rows.isEmpty else { return }

        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: entity.tableName),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "on_conflict", value: "id")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(rows)

        _ = try await performEmptyRequest(request: request)
    }

    private func configuration() throws -> MistiaSyncConfiguration {
        guard let configuration = configurationProvider() else {
            throw SupabaseServiceError.configurationMissing
        }
        return configuration
    }

    private func authorizedRequest(
        url: URL,
        session: SupabaseAuthSession
    ) -> URLRequest {
        let apiKey = configurationProvider()?.anonKey ?? ""
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performEmptyRequest(
        request: URLRequest
    ) async throws -> HTTPURLResponse {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.serverMessage("Supabase request failed with status \(httpResponse.statusCode).")
        }

        return httpResponse
    }

    private func performRequest<Response: Decodable>(
        request: URLRequest
    ) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? decoder.decode(SupabaseServiceErrorResponse.self, from: data) {
                throw SupabaseServiceError.serverMessage(error.errorDescription ?? error.message ?? "Supabase request failed.")
            }
            throw SupabaseServiceError.serverMessage("Supabase request failed with status \(httpResponse.statusCode).")
        }

        return try decoder.decode(Response.self, from: data)
    }
}

private struct DeletePatch: Encodable {
    let updatedAt: Date
    let deletedAt: Date
}
