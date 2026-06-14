import XCTest
@testable import Mistia

final class FamilyRemoteServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(FamilyRemoteServiceURLProtocol.self)
        FamilyRemoteServiceURLProtocol.reset()
    }

    override func tearDown() {
        FamilyRemoteServiceURLProtocol.reset()
        URLProtocol.unregisterClass(FamilyRemoteServiceURLProtocol.self)
        super.tearDown()
    }

    func testAccessibleFinanceSnapshotFiltersTransactionRowsByRequestedOwners() async throws {
        let firstUserID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let secondUserID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let service = FamilyRemoteService {
            MistiaSyncConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                anonKey: "anon-key"
            )
        }
        let session = SupabaseAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "bearer",
            expiresAt: nil,
            user: SupabaseAuthUser(id: UUID(), email: nil, userMetadata: nil)
        )

        _ = try await service.fetchAccessibleFinanceSnapshot(
            userIDs: [firstUserID, secondUserID],
            session: session
        )

        let transactionRequest = try XCTUnwrap(
            FamilyRemoteServiceURLProtocol.capturedRequests()
                .first { $0.url?.path == "/rest/v1/ledger_transactions" }
        )
        let queryItems = URLComponents(
            url: try XCTUnwrap(transactionRequest.url),
            resolvingAgainstBaseURL: false
        )?.queryItems

        XCTAssertEqual(
            queryItems?.first(where: { $0.name == "user_id" })?.value,
            "in.(\(firstUserID.uuidString.lowercased()),\(secondUserID.uuidString.lowercased()))"
        )
        XCTAssertEqual(queryItems?.first(where: { $0.name == "order" })?.value, "updated_at.asc")
    }
}

private final class FamilyRemoteServiceURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []

    static func reset() {
        lock.lock()
        requests = []
        lock.unlock()
    }

    static func capturedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.supabase.co"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
