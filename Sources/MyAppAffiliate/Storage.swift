import Foundation

/// Tiny key/value store the SDK uses to persist the device id and the attributed
/// affiliate id. Abstracted so the engine is testable without touching Keychain.
protocol KeyValueStore {
  func string(forKey key: String) -> String?
  func set(_ value: String?, forKey key: String)
}

/// Test/non-Apple fallback.
final class InMemoryStore: KeyValueStore {
  private var dict: [String: String] = [:]
  func string(forKey key: String) -> String? { dict[key] }
  func set(_ value: String?, forKey key: String) { dict[key] = value }
}

#if canImport(Security)
import Security

/// Keychain-backed store so attribution survives reinstalls (per docs/07).
final class KeychainStore: KeyValueStore {
  private let service: String
  init(service: String) { self.service = service }

  func string(forKey key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func set(_ value: String?, forKey key: String) {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(base as CFDictionary)
    guard let value, let data = value.data(using: .utf8) else { return }
    var add = base
    add[kSecValueData as String] = data
    SecItemAdd(add as CFDictionary, nil)
  }
}
#endif
