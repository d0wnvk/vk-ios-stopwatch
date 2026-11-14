import Foundation
import Security

/// Small, durable app state stored in the system Keychain.
///
/// Unlike UserDefaults and files in the app sandbox, Keychain items normally
/// remain on the device when a development build is removed and reinstalled.
/// The same development team and bundle identifier must be used on reinstall.
enum PersistentAppState {
    private static let service = "vk.stopwatch.persistent-state"

    static func load<Value: Decodable>(_ type: Value.Type = Value.self, forKey key: String) -> Value? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }

        return try? JSONDecoder().decode(Value.self, from: data)
    }

    static func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(identity as CFDictionary, values as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var newItem = identity
        values.forEach { newItem[$0.key] = $0.value }
        SecItemAdd(newItem as CFDictionary, nil)
    }
}
