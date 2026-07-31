import Foundation

/// Tiny key/value store the SDK uses to persist the device id, the attributed
/// affiliate id, and any attribution payload still waiting to be delivered.
/// Abstracted so the engine is testable without touching Keychain.
/// Implementations must be safe to call from multiple threads.
protocol KeyValueStore: Sendable {
  func string(forKey key: String) -> String?
  func set(_ value: String?, forKey key: String)
}

/// Test/non-Apple fallback.
final class InMemoryStore: KeyValueStore, @unchecked Sendable {
  private let lock = NSLock()
  private var dict: [String: String] = [:]

  func string(forKey key: String) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return dict[key]
  }

  func set(_ value: String?, forKey key: String) {
    lock.lock()
    defer { lock.unlock() }
    dict[key] = value
  }
}

#if canImport(Security)
  import Security

  /// Keychain-backed store so attribution survives reinstalls (per docs/07).
  final class KeychainStore: KeyValueStore, @unchecked Sendable {
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
        let data = item as? Data
      else { return nil }
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
      // Without this the item defaults to kSecAttrAccessibleWhenUnlocked, so a
      // background launch before the first unlock after a reboot reads nothing,
      // mints a fresh device id, and silently detaches the attribution.
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(add as CFDictionary, nil)
    }
  }
#endif
