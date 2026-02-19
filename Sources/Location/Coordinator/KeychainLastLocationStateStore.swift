import CioInternalCommon
import Foundation
import Security

/// Persists `LastLocationState` in the Keychain as a single item.
final class KeychainLastLocationStateStore: LastLocationStateStore {
    private static let account = "lastLocationState"
    private static let defaultService = "io.customer.sdk.location"

    private let service: String
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(
        service: String = KeychainLastLocationStateStore.defaultService,
        jsonEncoder: JSONEncoder = KeychainLastLocationStateStore.makeEncoder(),
        jsonDecoder: JSONDecoder = KeychainLastLocationStateStore.makeDecoder()
    ) {
        self.service = service
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
    }

    func load() -> LastLocationState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data
        else {
            if status != errSecItemNotFound {
                // Log in debug if desired; avoid exposing keychain errors to callers.
            }
            return nil
        }
        return try? jsonDecoder.decode(LastLocationState.self, from: data)
    }

    func save(_ state: LastLocationState) {
        guard let data = try? jsonEncoder.encode(state) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account
        ]
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
