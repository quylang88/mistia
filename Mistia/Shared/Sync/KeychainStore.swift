import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Received unexpected keychain data."
        case .unhandledStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain error: \(status)"
        }
    }
}

struct KeychainStore {
    let service: String

    init(service: String = "vn.com.quyln.mistia.sync") {
        self.service = service
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainStoreError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unhandledStatus(status)
        }
    }

    func set(_ data: Data, for account: String) throws {
        let query = baseQuery(for: account)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.unhandledStatus(addStatus)
            }
        default:
            throw KeychainStoreError.unhandledStatus(updateStatus)
        }
    }

    func removeData(for account: String) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
