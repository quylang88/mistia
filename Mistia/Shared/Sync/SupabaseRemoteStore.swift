import Foundation

protocol MistiaRemoteStore {
    func fetchSnapshot(session: SupabaseAuthSession) async throws -> MistiaRemoteSnapshot
    func fetchRecord(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord?
    func create(
        _ record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord
    func conditionalUpdate(
        _ record: MistiaSyncUploadRecord,
        expectedVersion: Int64,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord?
    func conditionalDelete(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        expectedVersion: Int64,
        modifiedAt: Date,
        deviceID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord?
    func forceUpsert(
        _ record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord
}

struct SupabaseRemoteStore: MistiaRemoteStore {
    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let decoder = JSONDecoder.mistiaRemoteAPIDecoder
    private let encoder = JSONEncoder.mistiaRemoteAPIEncoder

    init(configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() }) {
        self.configurationProvider = configurationProvider
    }

    func fetchSnapshot(session: SupabaseAuthSession) async throws -> MistiaRemoteSnapshot {
        let wallets: [RemoteLedgerWallet] = try await fetchRows(entity: .wallet, session: session)
        let profiles: [RemoteCreditCardProfile] = try await fetchRows(entity: .creditCardProfile, session: session)
        let categories: [RemoteTransactionCategory] = try await fetchRows(entity: .category, session: session)
        let transactions: [RemoteLedgerTransaction] = try await fetchRows(entity: .transaction, session: session)
        let budgetPlans: [RemoteBudgetPlan] = try await fetchRows(entity: .budgetPlan, session: session)
        let savingsGoals: [RemoteSavingsGoal] = try await fetchRows(entity: .savingsGoal, session: session)
        let recurringBillPlans: [RemoteRecurringBillPlan] = try await fetchRows(entity: .recurringBillPlan, session: session)
        let installmentPlans: [RemoteInstallmentPlan] = try await fetchRows(entity: .installmentPlan, session: session)
        let dueOccurrences: [RemoteDueOccurrenceRecord] = try await fetchRows(entity: .dueOccurrenceRecord, session: session)

        return MistiaRemoteSnapshot(
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

    func fetchRecord(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        switch entity {
        case .wallet:
            return try await fetchSingleRow(entity: entity, recordID: recordID, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.wallet)
        case .creditCardProfile:
            return try await fetchSingleRow(entity: entity, recordID: recordID, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.creditCardProfile)
        case .category:
            return try await fetchSingleRow(entity: entity, recordID: recordID, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.category)
        case .transaction:
            return try await fetchSingleRow(entity: entity, recordID: recordID, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.transaction)
        case .budgetPlan:
            return try await fetchSingleRow(entity: entity, recordID: recordID, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.budgetPlan)
        case .savingsGoal:
            return try await fetchSingleRow(entity: entity, recordID: recordID, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.savingsGoal)
        case .recurringBillPlan:
            return try await fetchSingleRow(entity: entity, recordID: recordID, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.recurringBillPlan)
        case .installmentPlan:
            return try await fetchSingleRow(entity: entity, recordID: recordID, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.installmentPlan)
        case .dueOccurrenceRecord:
            return try await fetchSingleRow(entity: entity, recordID: recordID, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.dueOccurrence)
        }
    }

    func create(
        _ record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord {
        let prepared = record.preparedForCreate(
            deviceID: record.lastModifiedByDeviceID ?? MistiaSyncDeviceIdentity.current()
        )

        switch prepared {
        case .wallet(let row):
            return .wallet(try await createRow(row, entity: .wallet, subjectUserID: subjectUserID, session: session))
        case .creditCardProfile(let row):
            return .creditCardProfile(try await createRow(row, entity: .creditCardProfile, subjectUserID: subjectUserID, session: session))
        case .category(let row):
            return .category(try await createRow(row, entity: .category, subjectUserID: subjectUserID, session: session))
        case .transaction(let row):
            return .transaction(try await createRow(row, entity: .transaction, subjectUserID: subjectUserID, session: session))
        case .budgetPlan(let row):
            return .budgetPlan(try await createRow(row, entity: .budgetPlan, subjectUserID: subjectUserID, session: session))
        case .savingsGoal(let row):
            return .savingsGoal(try await createRow(row, entity: .savingsGoal, subjectUserID: subjectUserID, session: session))
        case .recurringBillPlan(let row):
            return .recurringBillPlan(try await createRow(row, entity: .recurringBillPlan, subjectUserID: subjectUserID, session: session))
        case .installmentPlan(let row):
            return .installmentPlan(try await createRow(row, entity: .installmentPlan, subjectUserID: subjectUserID, session: session))
        case .dueOccurrence(let row):
            return .dueOccurrence(try await createRow(row, entity: .dueOccurrenceRecord, subjectUserID: subjectUserID, session: session))
        }
    }

    func conditionalUpdate(
        _ record: MistiaSyncUploadRecord,
        expectedVersion: Int64,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        let nextVersion = expectedVersion + 1
        let prepared = record.preparedForMutation(
            nextVersion: nextVersion,
            deviceID: record.lastModifiedByDeviceID ?? MistiaSyncDeviceIdentity.current()
        )

        switch prepared {
        case .wallet(let row):
            return try await updateRow(row, entity: .wallet, expectedVersion: expectedVersion, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.wallet)
        case .creditCardProfile(let row):
            return try await updateRow(row, entity: .creditCardProfile, expectedVersion: expectedVersion, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.creditCardProfile)
        case .category(let row):
            return try await updateRow(row, entity: .category, expectedVersion: expectedVersion, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.category)
        case .transaction(let row):
            return try await updateRow(row, entity: .transaction, expectedVersion: expectedVersion, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.transaction)
        case .budgetPlan(let row):
            return try await updateRow(row, entity: .budgetPlan, expectedVersion: expectedVersion, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.budgetPlan)
        case .savingsGoal(let row):
            return try await updateRow(row, entity: .savingsGoal, expectedVersion: expectedVersion, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.savingsGoal)
        case .recurringBillPlan(let row):
            return try await updateRow(row, entity: .recurringBillPlan, expectedVersion: expectedVersion, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.recurringBillPlan)
        case .installmentPlan(let row):
            return try await updateRow(row, entity: .installmentPlan, expectedVersion: expectedVersion, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.installmentPlan)
        case .dueOccurrence(let row):
            return try await updateRow(row, entity: .dueOccurrenceRecord, expectedVersion: expectedVersion, subjectUserID: subjectUserID, session: session).map(MistiaSyncUploadRecord.dueOccurrence)
        }
    }

    func conditionalDelete(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        expectedVersion: Int64,
        modifiedAt: Date,
        deviceID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: entity.tableName),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(recordID.uuidString.lowercased())"),
            URLQueryItem(name: "user_id", value: "eq.\(subjectUserID.uuidString.lowercased())"),
            URLQueryItem(name: "sync_version", value: "eq.\(expectedVersion)")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "PATCH"
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        if entity == .transaction {
            request.httpBody = try encoder.encode(
                TransactionDeletePatch(
                    updatedAt: modifiedAt,
                    deletedAt: modifiedAt,
                    syncVersion: expectedVersion + 1,
                    lastModifiedByDeviceID: deviceID,
                    lastModifiedByUserID: session.user.id
                )
            )
        } else {
            request.httpBody = try encoder.encode(
                DeletePatch(
                    updatedAt: modifiedAt,
                    deletedAt: modifiedAt,
                    syncVersion: expectedVersion + 1,
                    lastModifiedByDeviceID: deviceID
                )
            )
        }

        switch entity {
        case .wallet:
            let rows: [RemoteLedgerWallet] = try await performRequest(request: request)
            return rows.first.map(MistiaSyncUploadRecord.wallet)
        case .creditCardProfile:
            let rows: [RemoteCreditCardProfile] = try await performRequest(request: request)
            return rows.first.map(MistiaSyncUploadRecord.creditCardProfile)
        case .category:
            let rows: [RemoteTransactionCategory] = try await performRequest(request: request)
            return rows.first.map(MistiaSyncUploadRecord.category)
        case .transaction:
            let rows: [RemoteLedgerTransaction] = try await performRequest(request: request)
            return rows.first.map(MistiaSyncUploadRecord.transaction)
        case .budgetPlan:
            let rows: [RemoteBudgetPlan] = try await performRequest(request: request)
            return rows.first.map(MistiaSyncUploadRecord.budgetPlan)
        case .savingsGoal:
            let rows: [RemoteSavingsGoal] = try await performRequest(request: request)
            return rows.first.map(MistiaSyncUploadRecord.savingsGoal)
        case .recurringBillPlan:
            let rows: [RemoteRecurringBillPlan] = try await performRequest(request: request)
            return rows.first.map(MistiaSyncUploadRecord.recurringBillPlan)
        case .installmentPlan:
            let rows: [RemoteInstallmentPlan] = try await performRequest(request: request)
            return rows.first.map(MistiaSyncUploadRecord.installmentPlan)
        case .dueOccurrenceRecord:
            let rows: [RemoteDueOccurrenceRecord] = try await performRequest(request: request)
            return rows.first.map(MistiaSyncUploadRecord.dueOccurrence)
        }
    }

    func forceUpsert(
        _ record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord {
        switch record {
        case .wallet(let row):
            return .wallet(try await upsertRow(row, entity: .wallet, subjectUserID: subjectUserID, session: session))
        case .creditCardProfile(let row):
            return .creditCardProfile(try await upsertRow(row, entity: .creditCardProfile, subjectUserID: subjectUserID, session: session))
        case .category(let row):
            return .category(try await upsertRow(row, entity: .category, subjectUserID: subjectUserID, session: session))
        case .transaction(let row):
            return .transaction(try await upsertRow(row, entity: .transaction, subjectUserID: subjectUserID, session: session))
        case .budgetPlan(let row):
            return .budgetPlan(try await upsertRow(row, entity: .budgetPlan, subjectUserID: subjectUserID, session: session))
        case .savingsGoal(let row):
            return .savingsGoal(try await upsertRow(row, entity: .savingsGoal, subjectUserID: subjectUserID, session: session))
        case .recurringBillPlan(let row):
            return .recurringBillPlan(try await upsertRow(row, entity: .recurringBillPlan, subjectUserID: subjectUserID, session: session))
        case .installmentPlan(let row):
            return .installmentPlan(try await upsertRow(row, entity: .installmentPlan, subjectUserID: subjectUserID, session: session))
        case .dueOccurrence(let row):
            return .dueOccurrence(try await upsertRow(row, entity: .dueOccurrenceRecord, subjectUserID: subjectUserID, session: session))
        }
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

        do {
            return try await performRequest(request: authorizedRequest(url: url, session: session))
        } catch let error as DecodingError {
            throw SupabaseServiceError.serverMessage(
                "[GET \(entity.tableName)] Failed to decode remote data: \(describeDecodingError(error))"
            )
        } catch {
            throw error
        }
    }

    private func fetchSingleRow<Row: MistiaRemoteRow>(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> Row? {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: entity.tableName),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "id", value: "eq.\(recordID.uuidString.lowercased())"),
            URLQueryItem(name: "user_id", value: "eq.\(subjectUserID.uuidString.lowercased())"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        let rows: [Row] = try await performRequest(request: authorizedRequest(url: url, session: session))
        return rows.first
    }

    private func createRow<Row: MistiaRemoteRow>(
        _ row: Row,
        entity: MistiaSyncEntity,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> Row {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: entity.tableName),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(subjectUserID.uuidString.lowercased())")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode([row])

        let rows: [Row] = try await performRequest(request: request)
        guard let created = rows.first else {
            throw SupabaseServiceError.invalidResponse
        }
        return created
    }

    private func updateRow<Row: MistiaRemoteRow>(
        _ row: Row,
        entity: MistiaSyncEntity,
        expectedVersion: Int64,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> Row? {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: entity.tableName),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(row.id.uuidString.lowercased())"),
            URLQueryItem(name: "user_id", value: "eq.\(subjectUserID.uuidString.lowercased())"),
            URLQueryItem(name: "sync_version", value: "eq.\(expectedVersion)")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "PATCH"
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(row)

        let rows: [Row] = try await performRequest(request: request)
        return rows.first
    }

    private func upsertRow<Row: MistiaRemoteRow>(
        _ row: Row,
        entity: MistiaSyncEntity,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> Row {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: entity.tableName),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "on_conflict", value: "id"),
            URLQueryItem(name: "user_id", value: "eq.\(subjectUserID.uuidString.lowercased())")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode([row])

        let rows: [Row] = try await performRequest(request: request)
        guard let upserted = rows.first else {
            throw SupabaseServiceError.invalidResponse
        }
        return upserted
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performRequest<Response: Decodable>(
        request: URLRequest
    ) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw syncRequestErrorMessage(
                request: request,
                statusCode: httpResponse.statusCode,
                data: data
            )
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func syncRequestErrorMessage(
        request: URLRequest,
        statusCode: Int,
        data: Data
    ) -> SupabaseServiceError {
        let operation = request.httpMethod ?? "REQUEST"
        let tableName = request.url?.lastPathComponent ?? "unknown-table"

        let responseMessage: String? = {
            if let error = try? decoder.decode(SupabaseServiceErrorResponse.self, from: data) {
                return error.errorDescription ?? error.message
            }

            let rawBody = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rawBody?.isEmpty == false ? rawBody : nil
        }()

        let message = responseMessage ?? "The sync request failed."
        return .serverMessage("[\(operation) \(tableName)] HTTP \(statusCode): \(message)")
    }

    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(_, let context):
            return "type mismatch at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(_, let context):
            return "missing value at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "invalid data at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return "unknown decoding failure"
        }
    }

    private func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "root" : path
    }
}

private struct DeletePatch: Encodable {
    let updatedAt: Date
    let deletedAt: Date
    let syncVersion: Int64
    let lastModifiedByDeviceID: UUID
}

private struct TransactionDeletePatch: Encodable {
    let updatedAt: Date
    let deletedAt: Date
    let syncVersion: Int64
    let lastModifiedByDeviceID: UUID
    let lastModifiedByUserID: UUID

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
        case lastModifiedByUserID = "last_modified_by_user_id"
    }
}
