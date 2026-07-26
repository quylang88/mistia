import XCTest
@testable import Mistia

final class SupabaseRemoteStoreDeletePayloadTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(SupabaseRemoteStoreDeleteURLProtocol.self)
        SupabaseRemoteStoreDeleteURLProtocol.reset()
    }

    override func tearDown() {
        SupabaseRemoteStoreDeleteURLProtocol.reset()
        URLProtocol.unregisterClass(SupabaseRemoteStoreDeleteURLProtocol.self)
        super.tearDown()
    }

    func testCategoryDeletePatchUsesDatabaseColumnNames() async throws {
        let store = SupabaseRemoteStore {
            MistiaSyncConfiguration(
                projectURL: URL(string: "https://delete-payload-test.supabase.co")!,
                anonKey: "anon-key"
            )
        }
        let userID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let session = SupabaseAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "bearer",
            expiresAt: nil,
            user: SupabaseAuthUser(id: userID, email: nil, userMetadata: nil)
        )

        _ = try await store.conditionalDelete(
            entity: .category,
            recordID: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
            subjectUserID: userID,
            expectedVersion: 3,
            modifiedAt: Date(timeIntervalSince1970: 1_780_000_000),
            deviceID: UUID(uuidString: "30000000-0000-4000-8000-000000000003")!,
            session: session
        )

        let request = try XCTUnwrap(SupabaseRemoteStoreDeleteURLProtocol.capturedRequest())
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(
            Set(payload.keys),
            ["updated_at", "deleted_at", "sync_version", "last_modified_by_device_id"]
        )
    }
}

private final class SupabaseRemoteStoreDeleteURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var request: URLRequest?

    static func reset() {
        lock.lock()
        request = nil
        lock.unlock()
    }

    static func capturedRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "delete-payload-test.supabase.co"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.request = request
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
