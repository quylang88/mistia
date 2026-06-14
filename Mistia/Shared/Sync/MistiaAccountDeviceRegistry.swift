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

        let trimmedModel = modelDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? "iPhone" : trimmedModel
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
        bundle: Bundle = .main,
        device: UIDevice = .current,
        modelIdentifierProvider: () -> String = currentModelIdentifier
    ) -> MistiaAccountDevice {
        let identifier = modelIdentifierProvider()

        return MistiaAccountDevice(
            userID: session.user.id,
            deviceID: deviceID,
            sessionID: sessionID(fromAccessToken: session.accessToken),
            deviceName: device.name,
            modelIdentifier: identifier,
            modelDisplayName: modelDisplayName(for: identifier, fallbackDevice: device),
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            appBuild: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
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

    private static func modelDisplayName(for identifier: String, fallbackDevice device: UIDevice) -> String {
        let iPhoneModelNames: [String: String] = [
            "iPhone10,1": "iPhone 8",
            "iPhone10,2": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X",
            "iPhone10,4": "iPhone 8",
            "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,6": "iPhone X",
            "iPhone11,2": "iPhone XS",
            "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max",
            "iPhone11,8": "iPhone XR",
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone12,8": "iPhone SE (2nd generation)",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,6": "iPhone SE (3rd generation)",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
            "iPhone18,1": "iPhone 17 Pro",
            "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17",
            "iPhone18,4": "iPhone Air",
            "iPhone18,5": "iPhone 17e"
        ]

        if let modelName = iPhoneModelNames[identifier] {
            return modelName
        }

        if identifier.hasPrefix("iPhone") {
            return "iPhone"
        }

        let localizedModel = device.localizedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return localizedModel.isEmpty ? "iPhone" : localizedModel
    }

    private static func currentModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
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
