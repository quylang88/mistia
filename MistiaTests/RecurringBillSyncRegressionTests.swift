import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class RecurringBillSyncRegressionTests: XCTestCase {
    func testPauseSurvivesRepeatedAutomaticSync() async throws {
        try await assertEditSurvivesSync { bill in
            bill.isPaused = true
            bill.pausedAt = bill.updatedAt
            bill.resumeStartMonth = nil
        }
    }

    func testResumeClearsPauseDateAndSurvivesRepeatedSync() async throws {
        var remote = makeRemoteBill()
        remote.isPaused = true
        remote.pausedAt = remote.createdAt
        try await assertEditSurvivesSync(remote: remote) { bill in
            bill.isPaused = false
            bill.pausedAt = nil
            bill.resumeStartMonth = bill.updatedAt
        }
    }

    func testClearedAmountSurvivesPatchResponseAndRepeatedSync() async throws {
        try await assertEditSurvivesSync { $0.amountMinor = nil }
    }

    func testChangedAmountSurvivesRepeatedSync() async throws {
        try await assertEditSurvivesSync { $0.amountMinor = 9_500 }
    }

    func testDisablingAutoPayClearsItsDayOnCloud() async throws {
        try await assertEditSurvivesSync { bill in
            bill.autoPayEnabled = false
            bill.autoPayDay = nil
        }
    }

    func testOneTimeBillClearsDeadlineAndAutoPayDateOnCloud() async throws {
        try await assertEditSurvivesSync(remote: makeRemoteBill(oneTime: true)) { bill in
            bill.hasExplicitDueDate = false
            bill.dueDate = nil
            bill.autoPayEnabled = false
            bill.autoPayDate = nil
        }
    }

    func testOneTimeBillDateEditsSurviveRepeatedSync() async throws {
        try await assertEditSurvivesSync(remote: makeRemoteBill(oneTime: true)) { bill in
            bill.paymentStartDate = bill.paymentStartDate?.addingTimeInterval(86_400)
            bill.dueDate = bill.dueDate?.addingTimeInterval(86_400)
            bill.autoPayDate = bill.autoPayDate?.addingTimeInterval(86_400)
        }
    }

    func testSwitchToRecurringClearsOneTimeDatesOnCloud() async throws {
        try await assertEditSurvivesSync(remote: makeRemoteBill(oneTime: true)) { bill in
            bill.scheduleKind = .recurring
            bill.paymentStartDate = nil
            bill.dueDate = nil
            bill.autoPayDate = nil
            bill.autoPayDay = 12
            bill.firstScheduledMonth = bill.updatedAt
        }
    }

    func testNameAndRecurringScheduleEditsSurviveRepeatedSync() async throws {
        try await assertEditSurvivesSync { bill in
            bill.name = "Updated electricity bill"
            bill.paymentStartDay = 7
            bill.dueDay = 20
            bill.autoPayDay = 18
            bill.frequencyMonths = 3
        }
    }

    func testNewerPauseWithoutOutboxEntryIsRecoveredBySync() async throws {
        try await assertEditSurvivesSync(enqueueMutation: false) { bill in
            bill.isPaused = true
            bill.pausedAt = bill.updatedAt
        }
    }

    private func assertEditSurvivesSync(
        remote: RemoteRecurringBillPlan? = nil,
        enqueueMutation: Bool = true,
        edit: (RecurringBillPlan) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let remote = remote ?? makeRemoteBill()
        let schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        try MistiaSyncLocalStore.applyRemoteRecord(.recurringBillPlan(remote), in: container)
        let context = ModelContext(container)
        let bill = try XCTUnwrap(try context.fetch(FetchDescriptor<RecurringBillPlan>()).first)
        bill.updatedAt = remote.updatedAt.addingTimeInterval(600)
        edit(bill)
        try context.save()

        let mutation = MistiaSyncMutation(
            entity: .recurringBillPlan, recordID: bill.id, subjectUserID: remote.userID,
            kind: .upsert, modifiedAt: bill.updatedAt, baseVersion: remote.syncVersion
        )
        let expected = try XCTUnwrap(MistiaSyncLocalStore.exportRecord(for: mutation, from: container))
        try RecurringBillSyncURLProtocol.seed(remote)
        URLProtocol.registerClass(RecurringBillSyncURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RecurringBillSyncURLProtocol.self)
            RecurringBillSyncURLProtocol.reset()
        }
        let suiteName = "MistiaTests.BillSync.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let outbox = MistiaSyncOutbox(defaults: defaults, key: "outbox")
        if enqueueMutation { outbox.enqueue(mutation) }
        let remoteStore = SupabaseRemoteStore {
            MistiaSyncConfiguration(
                projectURL: URL(string: "https://bill-sync-test.supabase.co")!,
                anonKey: "test-anon-key"
            )
        }
        let coordinator = SyncCoordinator(
            modelContainer: container, remoteStore: remoteStore, outbox: outbox, deviceID: UUID()
        )
        let session = SupabaseAuthSession(
            accessToken: "test-access-token", refreshToken: "test-refresh-token", tokenType: "bearer",
            expiresAt: nil, user: SupabaseAuthUser(id: remote.userID, email: nil, userMetadata: nil)
        )

        for _ in 0..<3 {
            _ = try await coordinator.sync(session: session)
            let saved = try XCTUnwrap(MistiaSyncLocalStore.exportRecord(for: mutation, from: container))
            XCTAssertEqual(saved.payloadFingerprint, expected.payloadFingerprint, file: file, line: line)
        }
        let cloud = try await remoteStore.fetchRecord(
            entity: .recurringBillPlan, recordID: bill.id, subjectUserID: remote.userID, session: session
        )
        XCTAssertEqual(cloud?.payloadFingerprint, expected.payloadFingerprint, file: file, line: line)
        XCTAssertEqual(cloud?.syncVersion, remote.syncVersion + 1, file: file, line: line)
        XCTAssertEqual(
            RecurringBillSyncURLProtocol.writeMethods(), [enqueueMutation ? "PATCH" : "POST"],
            "A saved edit should upload once and remain stable on subsequent pulls", file: file, line: line
        )
        XCTAssertTrue(outbox.allMutations.isEmpty, file: file, line: line)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncConflict>()).isEmpty, file: file, line: line)
    }

    private func makeRemoteBill(oneTime: Bool = false) -> RemoteRecurringBillPlan {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        return RemoteRecurringBillPlan(
            userID: UUID(), id: UUID(), name: "Electricity", iconSymbolName: "bolt",
            amountMinor: 4_200, dueDay: 15,
            scheduleKindRawValue: oneTime ? "oneTime" : "recurring", paymentStartDay: 5,
            paymentStartDate: oneTime ? date : nil, firstScheduledMonth: oneTime ? nil : date,
            hasExplicitDueDate: true, dueDate: oneTime ? date.addingTimeInterval(864_000) : nil,
            autoPayEnabled: true, autoPayDay: oneTime ? nil : 10,
            autoPayDate: oneTime ? date.addingTimeInterval(432_000) : nil,
            frequencyMonths: 1, currencyCode: "JPY", isArchived: false, isPaused: false,
            createdAt: date, updatedAt: date, syncVersion: 1
        )
    }
}

// Exercise the real HTTP payload and response decoder. Like a database PATCH,
// this server changes only submitted columns, retaining omitted values.
private final class RecurringBillSyncURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var row: [String: Any] = [:]
    private static var methods: [String] = []

    static func seed(_ bill: RemoteRecurringBillPlan) throws {
        let data = try JSONEncoder.mistiaRemoteAPIEncoder.encode(bill)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        lock.lock()
        defer { lock.unlock() }
        row = payload
        methods = []
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        row = [:]
        methods = []
    }

    static func writeMethods() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return methods
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "bill-sync-test.supabase.co"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let data = try responseData()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func responseData() throws -> Data {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let method = request.httpMethod ?? "GET"
        guard request.url?.lastPathComponent == "recurring_bill_plans" else {
            guard method == "GET" else { throw URLError(.unsupportedURL) }
            return Data("[]".utf8)
        }
        if method == "PATCH" || method == "POST" {
            let body = try requestBody()
            let object = try JSONSerialization.jsonObject(with: body)
            let payload = try XCTUnwrap((object as? [String: Any]) ?? (object as? [[String: Any]])?.first)
            if method == "PATCH" {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                let expectedVersion = query?.first(where: { $0.name == "sync_version" })?.value
                let version = try XCTUnwrap(Self.row["sync_version"] as? NSNumber)
                guard expectedVersion == "eq.\(version.int64Value)" else { return Data("[]".utf8) }
            }
            Self.row.merge(payload) { _, new in new }
            Self.methods.append(method)
        } else if method != "GET" {
            throw URLError(.unsupportedURL)
        }
        return try JSONSerialization.data(withJSONObject: [Self.row])
    }

    private func requestBody() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { return data }
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    override func stopLoading() {}
}
