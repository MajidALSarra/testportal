import Foundation
import Security

/// The API key lives in the Keychain (the iOS twin of Android's EncryptedSharedPreferences), in a keychain
/// access group shared by the app and the share extension so both can talk to /api/v1.
enum Keychain {
    static let service = "com.folderbird.companion"

    /// "<TeamID>.com.folderbird.companion". The team prefix is only known at signing time, so both Info.plists
    /// carry `AppIdentifierPrefix = $(AppIdentifierPrefix)` and it is read back here. Unsigned builds (CI /
    /// a bare simulator run) have no prefix → nil → the item is stored without a group.
    static var accessGroup: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String else { return nil }
        let prefix = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, !prefix.contains("$(") else { return nil }
        return prefix + service
    }

    /// The group first, then no group: an unsigned build has no entitlement and SecItemAdd answers -34018
    /// (errSecMissingEntitlement) for the grouped query, so the ungrouped one is the fallback.
    private static var candidateGroups: [String?] { accessGroup.map { [$0, nil] } ?? [nil] }

    private static func baseQuery(_ key: String, group: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let g = group { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    static func set(_ key: String, _ value: String) {
        for group in candidateGroups { SecItemDelete(baseQuery(key, group: group) as CFDictionary) }
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        for group in candidateGroups {
            var add = baseQuery(key, group: group)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly   // never migrates via backup
            if SecItemAdd(add as CFDictionary, nil) == errSecSuccess { return }
        }
    }

    static func get(_ key: String) -> String? {
        for group in candidateGroups {
            var q = baseQuery(key, group: group)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    static func remove(_ key: String) { set(key, "") }
}
