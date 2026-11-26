import Foundation
import Security

/// Plugin settings of type "secret" (API tokens), kept in the login Keychain rather than
/// in user defaults. One generic-password item per plugin and key.
enum PluginSecrets {
  private static func query(plugin: String, key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "Altools plugin \(plugin)",
     kSecAttrAccount as String: key]
  }

  static func get(plugin: String, key: String) -> String? {
    var q = query(plugin: plugin, key: key)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// An empty value deletes the item.
  static func set(_ value: String, plugin: String, key: String) {
    let q = query(plugin: plugin, key: key)
    SecItemDelete(q as CFDictionary)
    guard !value.isEmpty else { return }
    var add = q
    add[kSecValueData as String] = Data(value.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(add as CFDictionary, nil)
  }
}
