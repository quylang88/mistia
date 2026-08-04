import Foundation
import UIKit

enum MistiaAccountDeviceStatus: Equatable {
    case signedIn
    case signedOut
    case forgotten
    case unknown
}

struct MistiaAccountDevice: Codable, Equatable, Identifiable {
    let userID: UUID
    let deviceID: UUID
    let sessionID: UUID?
    let deviceName: String
    let modelIdentifier: String
    let modelDisplayName: String
    let systemName: String
    let systemVersion: String
    let appVersion: String
    let appBuild: String
    let signedInAt: Date
    let lastSeenAt: Date
    var signedOutAt: Date?
    var forgetAt: Date?
    var remoteSignOutRequestedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    var id: UUID { deviceID }

    var status: MistiaAccountDeviceStatus {
        if forgetAt != nil {
            return .forgotten
        }
        if signedOutAt != nil {
            return .signedOut
        }
        return .signedIn
    }

    var displayName: String {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        return "iPhone"
    }

    var modelListDisplayName: String {
        let displayName = modelDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        if !identifier.isEmpty, Self.isGenericModelDisplayName(displayName, for: identifier) {
            return identifier
        }

        if !displayName.isEmpty {
            return displayName
        }

        return identifier
    }

    func isCurrentDevice(currentDeviceID: UUID = MistiaSyncDeviceIdentity.current()) -> Bool {
        deviceID == currentDeviceID
    }

    func requiresLocalSignOut(currentDeviceID: UUID = MistiaSyncDeviceIdentity.current()) -> Bool {
        isCurrentDevice(currentDeviceID: currentDeviceID)
            && (remoteSignOutRequestedAt != nil || forgetAt != nil)
    }

    static func current(
        session: SupabaseAuthSession,
        now: Date = .now,
        deviceID: UUID = MistiaSyncDeviceIdentity.current(),
        deviceInfo: CurrentDeviceInfo = .current()
    ) -> MistiaAccountDevice {
        MistiaAccountDevice(
            userID: session.user.id,
            deviceID: deviceID,
            sessionID: sessionID(fromAccessToken: session.accessToken),
            deviceName: deviceInfo.deviceName,
            modelIdentifier: deviceInfo.modelIdentifier,
            modelDisplayName: deviceInfo.modelDisplayName,
            systemName: deviceInfo.systemName,
            systemVersion: deviceInfo.systemVersion,
            appVersion: deviceInfo.appVersion,
            appBuild: deviceInfo.appBuild,
            signedInAt: now,
            lastSeenAt: now,
            signedOutAt: nil,
            forgetAt: nil,
            remoteSignOutRequestedAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    static func sessionID(fromAccessToken token: String) -> UUID? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2,
              let payloadData = base64URLDecodedData(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let rawSessionID = object["session_id"] as? String
        else {
            return nil
        }
        return UUID(uuidString: rawSessionID)
    }

    private static func base64URLDecodedData(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    private static func isGenericModelDisplayName(_ displayName: String, for identifier: String) -> Bool {
        guard !displayName.isEmpty else { return false }
        return identifier.hasPrefix(displayName)
            && displayName.rangeOfCharacter(from: .decimalDigits) == nil
    }


    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceID = "device_id"
        case sessionID = "session_id"
        case deviceName = "device_name"
        case modelIdentifier = "model_identifier"
        case modelDisplayName = "model_display_name"
        case systemName = "system_name"
        case systemVersion = "system_version"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case signedInAt = "signed_in_at"
        case lastSeenAt = "last_seen_at"
        case signedOutAt = "signed_out_at"
        case forgetAt = "forget_at"
        case remoteSignOutRequestedAt = "remote_sign_out_requested_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

protocol AccountDeviceRegistryServicing {
    func registerCurrentDevice(session: SupabaseAuthSession) async throws -> MistiaAccountDevice
    func fetchDevices(session: SupabaseAuthSession) async throws -> [MistiaAccountDevice]
    func fetchCurrentDevice(session: SupabaseAuthSession) async throws -> MistiaAccountDevice?
    func requestSignOut(deviceID: UUID, session: SupabaseAuthSession) async throws -> MistiaAccountDevice
    func forgetDevice(deviceID: UUID, session: SupabaseAuthSession) async throws
    func markCurrentDeviceSignedOut(session: SupabaseAuthSession?) async throws
}

struct MistiaAccountDeviceRegistryService: AccountDeviceRegistryServicing {
    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let urlSession: URLSession
    private let encoder = JSONEncoder.mistiaRemoteAPIEncoder
    private let decoder = JSONDecoder.mistiaRemoteAPIDecoder
    private let now: () -> Date

    init(
        configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() },
        urlSession: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.configurationProvider = configurationProvider
        self.urlSession = urlSession
        self.now = now
    }

    func registerCurrentDevice(session: SupabaseAuthSession) async throws -> MistiaAccountDevice {
        let device = MistiaAccountDevice.current(session: session, now: now())
        let configuration = try configuration()
        var components = tableComponents(configuration: configuration)
        components.queryItems = [
            URLQueryItem(name: "on_conflict", value: "user_id,device_id")
        ]
        var request = authorizedRequest(url: try resolvedURL(components), session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(AccountDeviceUpsertPayload(device: device))
        let rows: [MistiaAccountDevice] = try await performRequest(request)
        return rows.first ?? device
    }

    func fetchDevices(session: SupabaseAuthSession) async throws -> [MistiaAccountDevice] {
        let configuration = try configuration()
        var components = tableComponents(configuration: configuration)
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "forget_at", value: "is.null"),
            URLQueryItem(name: "order", value: "last_seen_at.desc")
        ]
        var request = authorizedRequest(url: try resolvedURL(components), session: session)
        request.httpMethod = "GET"
        return try await performRequest(request)
    }

    func fetchCurrentDevice(session: SupabaseAuthSession) async throws -> MistiaAccountDevice? {
        let configuration = try configuration()
        var components = tableComponents(configuration: configuration)
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "device_id", value: "eq.\(MistiaSyncDeviceIdentity.current().uuidString.lowercased())"),
            URLQueryItem(name: "limit", value: "1")
        ]
        var request = authorizedRequest(url: try resolvedURL(components), session: session)
        request.httpMethod = "GET"
        let rows: [MistiaAccountDevice] = try await performRequest(request)
        return rows.first
    }

    func requestSignOut(deviceID: UUID, session: SupabaseAuthSession) async throws -> MistiaAccountDevice {
        let rows = try await patchDevice(
            deviceID: deviceID,
            session: session,
            payload: AccountDevicePatch(
                remoteSignOutRequestedAt: now(),
                signedOutAt: nil,
                forgetAt: nil
            ),
            returnsRepresentation: true
        )
        return rows.first ?? MistiaAccountDevice.current(session: session, now: now(), deviceID: deviceID)
    }

    func forgetDevice(deviceID: UUID, session: SupabaseAuthSession) async throws {
        _ = try await patchDevice(
            deviceID: deviceID,
            session: session,
            payload: AccountDevicePatch(
                remoteSignOutRequestedAt: now(),
                signedOutAt: nil,
                forgetAt: now()
            ),
            returnsRepresentation: false
        )
    }

    func markCurrentDeviceSignedOut(session: SupabaseAuthSession?) async throws {
        guard let session else { return }
        _ = try await patchDevice(
            deviceID: MistiaSyncDeviceIdentity.current(),
            session: session,
            payload: AccountDevicePatch(
                remoteSignOutRequestedAt: nil,
                signedOutAt: now(),
                forgetAt: nil
            ),
            returnsRepresentation: false
        )
    }

    private func patchDevice(
        deviceID: UUID,
        session: SupabaseAuthSession,
        payload: AccountDevicePatch,
        returnsRepresentation: Bool
    ) async throws -> [MistiaAccountDevice] {
        let configuration = try configuration()
        var components = tableComponents(configuration: configuration)
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())"),
            URLQueryItem(name: "device_id", value: "eq.\(deviceID.uuidString.lowercased())")
        ]
        var request = authorizedRequest(url: try resolvedURL(components), session: session)
        request.httpMethod = "PATCH"
        request.setValue(returnsRepresentation ? "return=representation" : "return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(payload)
        if returnsRepresentation {
            return try await performRequest(request)
        }

        try await performEmptyRequest(request)
        return []
    }

    private func tableComponents(configuration: MistiaSyncConfiguration) -> URLComponents {
        URLComponents(
            url: configuration.restBaseURL.appending(path: "account_devices"),
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()
    }

    private func resolvedURL(_ components: URLComponents) throws -> URL {
        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }
        return url
    }

    private func configuration() throws -> MistiaSyncConfiguration {
        guard let configuration = configurationProvider() else {
            throw SupabaseServiceError.configurationMissing
        }
        return configuration
    }

    private func authorizedRequest(url: URL, session: SupabaseAuthSession) -> URLRequest {
        let apiKey = configurationProvider()?.anonKey ?? ""
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performRequest<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw requestError(request: request, statusCode: httpResponse.statusCode, data: data)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func performEmptyRequest(_ request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw requestError(request: request, statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func requestError(
        request: URLRequest,
        statusCode: Int,
        data: Data
    ) -> SupabaseServiceError {
        let operation = request.httpMethod ?? "REQUEST"
        let responseMessage: String? = {
            if let error = try? decoder.decode(SupabaseServiceErrorResponse.self, from: data) {
                return error.errorDescription ?? error.message
            }
            let rawBody = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rawBody?.isEmpty == false ? rawBody : nil
        }()
        return .serverMessage("[\(operation) account_devices] HTTP \(statusCode): \(responseMessage ?? "The account device request failed.")")
    }
}

private struct AccountDeviceUpsertPayload: Encodable {
    let device: MistiaAccountDevice

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: MistiaAccountDevice.CodingKeys.self)
        try container.encode(device.userID, forKey: .userID)
        try container.encode(device.deviceID, forKey: .deviceID)
        try container.encodeIfPresent(device.sessionID, forKey: .sessionID)
        try container.encode(device.deviceName, forKey: .deviceName)
        try container.encode(device.modelIdentifier, forKey: .modelIdentifier)
        try container.encode(device.modelDisplayName, forKey: .modelDisplayName)
        try container.encode(device.systemName, forKey: .systemName)
        try container.encode(device.systemVersion, forKey: .systemVersion)
        try container.encode(device.appVersion, forKey: .appVersion)
        try container.encode(device.appBuild, forKey: .appBuild)
        try container.encode(device.signedInAt, forKey: .signedInAt)
        try container.encode(device.lastSeenAt, forKey: .lastSeenAt)
        try container.encodeNil(forKey: .signedOutAt)
        try container.encodeNil(forKey: .forgetAt)
        try container.encodeNil(forKey: .remoteSignOutRequestedAt)
    }
}

private struct AccountDevicePatch: Encodable {
    let remoteSignOutRequestedAt: Date?
    let signedOutAt: Date?
    let forgetAt: Date?

    enum CodingKeys: String, CodingKey {
        case remoteSignOutRequestedAt = "remote_sign_out_requested_at"
        case signedOutAt = "signed_out_at"
        case forgetAt = "forget_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let remoteSignOutRequestedAt {
            try container.encode(remoteSignOutRequestedAt, forKey: .remoteSignOutRequestedAt)
        } else {
            try container.encodeNil(forKey: .remoteSignOutRequestedAt)
        }
        if let signedOutAt {
            try container.encode(signedOutAt, forKey: .signedOutAt)
        }
        if let forgetAt {
            try container.encode(forgetAt, forKey: .forgetAt)
        }
    }
}
