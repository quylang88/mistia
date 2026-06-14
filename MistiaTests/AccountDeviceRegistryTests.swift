import XCTest
@testable import Mistia

final class AccountDeviceRegistryTests: XCTestCase {
    override func tearDown() {
        AccountDeviceURLProtocol.requestHandler = nil
        AccountDeviceURLProtocol.capturedRequests = []
        super.tearDown()
    }

    func testSessionIDIsDecodedFromAccessTokenPayload() throws {
        let sessionID = UUID()
        let token = makeJWT(payload: ["session_id": sessionID.uuidString])

        XCTAssertEqual(MistiaAccountDevice.sessionID(fromAccessToken: token), sessionID)
    }

    func testCurrentDeviceUsesMarketingNameForKnownModelIdentifier() {
        let session = SupabaseAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "bearer",
            expiresAt: nil,
            user: SupabaseAuthUser(id: UUID(), email: nil, userMetadata: nil)
        )

        let device = MistiaAccountDevice.current(
            session: session,
            modelIdentifierProvider: { "iPhone16,2" }
        )

        XCTAssertEqual(device.modelIdentifier, "iPhone16,2")
        XCTAssertEqual(device.modelDisplayName, "iPhone 15 Pro Max")
    }

    func testCurrentDeviceUsesIdentifierInListsForUnmappedGenericIPhoneFallback() {
        let session = SupabaseAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "bearer",
            expiresAt: nil,
            user: SupabaseAuthUser(id: UUID(), email: nil, userMetadata: nil)
        )

        let device = MistiaAccountDevice.current(
            session: session,
            modelIdentifierProvider: { "iPhone99,9" }
        )

        XCTAssertEqual(device.modelIdentifier, "iPhone99,9")
        XCTAssertEqual(device.modelDisplayName, "iPhone")
        XCTAssertEqual(device.modelListDisplayName, "iPhone99,9")
    }

    func testDeviceStatusPrefersForgottenThenSignedOutThenActive() {
        let userID = UUID()
        let deviceID = UUID()
        let now = Date()

        let active = MistiaAccountDevice(
            userID: userID,
            deviceID: deviceID,
            sessionID: nil,
            deviceName: "Lan's iPhone",
            modelIdentifier: "iPhone16,2",
            modelDisplayName: "iPhone",
            systemName: "iOS",
            systemVersion: "26.4",
            appVersion: "1.0",
            appBuild: "1",
            signedInAt: now,
            lastSeenAt: now,
            signedOutAt: nil,
            forgetAt: nil,
            remoteSignOutRequestedAt: nil,
            createdAt: now,
            updatedAt: now
        )
        XCTAssertEqual(active.status, .signedIn)

        var signedOut = active
        signedOut.signedOutAt = now
        XCTAssertEqual(signedOut.status, .signedOut)

        var forgotten = signedOut
        forgotten.forgetAt = now
        XCTAssertEqual(forgotten.status, .forgotten)
    }

    func testDisplayNameUsesTrimmedDeviceNameWhenAvailable() {
        let device = MistiaAccountDevice.fixture(
            deviceName: "  Lan's Travel iPhone  ",
            modelDisplayName: "iPhone 16 Pro"
        )

        XCTAssertEqual(device.displayName, "Lan's Travel iPhone")
    }

    func testDisplayNameFallsBackToIPhoneWhenDeviceNameIsBlank() {
        let emptyDeviceName = MistiaAccountDevice.fixture(
            deviceName: "",
            modelDisplayName: "iPhone 16 Pro"
        )
        let whitespaceDeviceName = MistiaAccountDevice.fixture(
            deviceName: "  \n\t  ",
            modelDisplayName: "iPad"
        )

        XCTAssertEqual(emptyDeviceName.displayName, "iPhone")
        XCTAssertEqual(whitespaceDeviceName.displayName, "iPhone")
    }

    func testCurrentDeviceRequiresLocalSignOutWhenForgottenOrRemoteRequested() {
        let currentDeviceID = UUID()
        let now = Date()
        var device = MistiaAccountDevice.fixture(deviceID: currentDeviceID)

        XCTAssertFalse(device.requiresLocalSignOut(currentDeviceID: currentDeviceID))

        device.remoteSignOutRequestedAt = now
        XCTAssertTrue(device.requiresLocalSignOut(currentDeviceID: currentDeviceID))

        device.remoteSignOutRequestedAt = nil
        device.forgetAt = now
        XCTAssertTrue(device.requiresLocalSignOut(currentDeviceID: currentDeviceID))

        XCTAssertFalse(device.requiresLocalSignOut(currentDeviceID: UUID()))
    }

    func testSupabaseAuthServiceSignOutUsesLocalScope() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountDeviceURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let projectURL = try XCTUnwrap(URL(string: "https://example.supabase.co"))
        let keychain = KeychainStore(service: "vn.com.quyln.mistia.tests.\(UUID().uuidString)")
        let service = SupabaseAuthService(
            keychain: keychain,
            configurationProvider: {
                MistiaSyncConfiguration(projectURL: projectURL, anonKey: "anon-key")
            },
            urlSession: urlSession
        )
        let session = SupabaseAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "bearer",
            expiresAt: nil,
            user: SupabaseAuthUser(id: UUID(), email: nil, userMetadata: nil)
        )
        AccountDeviceURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let scope = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "scope" })?
                .value
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(url.path, "/auth/v1/logout")
            XCTAssertEqual(scope, "local")
            return (HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            try await service.signOut(session: session)
        } catch KeychainStoreError.unhandledStatus {
            // The simulator test runner can reject keychain cleanup; this test
            // only verifies the Supabase logout request scope.
        }

        XCTAssertEqual(AccountDeviceURLProtocol.capturedRequests.count, 1)
    }

    private func makeJWT(payload: [String: String]) -> String {
        [
            base64URL(["alg": "none", "typ": "JWT"]),
            base64URL(payload),
            ""
        ].joined(separator: ".")
    }

    private func base64URL(_ payload: [String: String]) -> String {
        let data = try! JSONEncoder().encode(payload)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class AccountDeviceURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedRequests.append(request)

        do {
            let handler = try XCTUnwrap(Self.requestHandler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension MistiaAccountDevice {
    static func fixture(
        deviceID: UUID = UUID(),
        deviceName: String = "Lan's iPhone",
        modelDisplayName: String = "iPhone"
    ) -> MistiaAccountDevice {
        let now = Date()
        return MistiaAccountDevice(
            userID: UUID(),
            deviceID: deviceID,
            sessionID: nil,
            deviceName: deviceName,
            modelIdentifier: "iPhone16,2",
            modelDisplayName: modelDisplayName,
            systemName: "iOS",
            systemVersion: "26.4",
            appVersion: "1.0",
            appBuild: "1",
            signedInAt: now,
            lastSeenAt: now,
            signedOutAt: nil,
            forgetAt: nil,
            remoteSignOutRequestedAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
