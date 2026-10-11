import Foundation
import Combine

/// Persisted settings + credentials. Settings live in the App Group's UserDefaults (shared with the share
/// extension); the API key lives in the shared Keychain group (see Keychain.swift). Mirrors Prefs.kt.
final class Prefs: ObservableObject {
    static let shared = Prefs()

    static let appGroup = "group.com.folderbird.companion"
    static let defaultBase = "https://folderbird.com"
    static let maxRecentFolders = 6

    private enum K {
        static let base = "base_url"
        static let key = "api_key"
        static let folder = "last_folder"
        static let theme = "theme_mode"
        static let verifier = "pkce_verifier"
        static let state = "pkce_state"
        static let redirect = "pkce_redirect"
        static let expires = "key_expires_at"
        static let signoutReason = "signed_out_reason"
        static let installId = "install_id"
        static let recentFolders = "recent_folders"
        static let installed = "installed"          // lives in the App Group container, which an uninstall wipes
        static let keyBase = "api_key_base"         // keychain: the server that issued the stored key
    }

    private let d: UserDefaults

    @Published var baseUrl: String {
        didSet {
            d.set(baseUrl, forKey: K.base)
            // The server a key was issued by is remembered next to the key (see revokeStale).
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Keychain.set(K.keyBase, normalizedBase) }
        }
    }
    /// Theme preference: "system" (follow the device), "light", or "dark".
    @Published var themeMode: String { didSet { d.set(themeMode, forKey: K.theme) } }
    /// The scoped API key used for all /api/v1 calls — from "Sign in with Folderbird" or pasted manually.
    @Published var apiKey: String {
        didSet {
            let k = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            Keychain.set(K.key, k)
            Keychain.set(K.keyBase, k.isEmpty ? "" : normalizedBase)
        }
    }

    private init() {
        d = UserDefaults(suiteName: Prefs.appGroup) ?? .standard
        baseUrl = d.string(forKey: K.base) ?? Prefs.defaultBase
        themeMode = d.string(forKey: K.theme) ?? "system"
        // iOS keeps keychain items across app deletion but wipes the App Group container, so a missing marker
        // means a fresh install: never adopt a previous install's key (Android's uninstall drops it too).
        if !d.bool(forKey: K.installed) {
            if let stale = Keychain.get(K.key), !stale.isEmpty {
                // Revoke it only against the server that issued it — never a default host.
                if let base = Keychain.get(K.keyBase), !base.isEmpty { Prefs.revokeStale(base: base, key: stale) }
                Keychain.remove(K.key)
                Keychain.remove(K.keyBase)
            }
            d.set(true, forKey: K.installed)
        }
        apiKey = Keychain.get(K.key) ?? ""
    }

    /// Best-effort server-side revoke of a key left behind by an earlier install; failures are ignored.
    private static func revokeStale(base: String, key: String) {
        guard let url = URL(string: normalizeBase(base) + "/app/revoke") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        Api.session.dataTask(with: req).resume()
    }

    /// Re-read what another process (the app vs. the share extension) may have changed.
    func reload() {
        let k = Keychain.get(K.key) ?? ""
        if k != apiKey { apiKey = k }
        let b = d.string(forKey: K.base) ?? Prefs.defaultBase
        if b != baseUrl { baseUrl = b }
        let t = d.string(forKey: K.theme) ?? "system"
        if t != themeMode { themeMode = t }
    }

    private func str(_ key: String) -> String { d.string(forKey: key) ?? "" }
    private func put(_ key: String, _ v: String) { d.set(v, forKey: key) }

    var lastUploadFolder: String { get { str(K.folder) } set { put(K.folder, newValue) } }
    /// Transient PKCE verifier, held only between launching the browser and the redirect coming back.
    var pendingVerifier: String { get { str(K.verifier) } set { put(K.verifier, newValue) } }
    var pendingState: String { get { str(K.state) } set { put(K.state, newValue) } }
    /// Redirect URI used for the in-flight sign-in; echoed to /app/token, which requires it to match the code.
    var pendingRedirect: String { get { str(K.redirect) } set { put(K.redirect, newValue) } }
    /// ISO-8601 expiry of the current key (from /app/token). Informational only — the server is the authority.
    var keyExpiresAt: String { get { str(K.expires) } set { put(K.expires, newValue) } }
    /// One-line reason shown once on the sign-in screen after an involuntary sign-out (expired/revoked key).
    var signedOutReason: String { get { str(K.signoutReason) } set { put(K.signoutReason, newValue) } }

    /// Stable per-install id (random UUID, generated once). Survives sign-out on purpose — it is what lets a
    /// re-sign-in retire this install's OLD key and nobody else's. Kept in the device-bound keychain, like the
    /// key it is paired with, so a backup restored onto a second device gets its own id instead of revoking
    /// the first device's key at its next sign-in.
    var installId: String {
        if let v = Keychain.get(K.installId), !v.isEmpty { return v }
        let fresh = UUID().uuidString.lowercased()
        Keychain.set(K.installId, fresh)
        return fresh
    }

    /// Most-recently-used upload folders, newest first (max 6). Powers the share screen's quick-pick chips.
    func recentFolders() -> [String] {
        str(K.recentFolders).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Record a folder as used: move it to the front, de-duplicate case-insensitively, cap at 6.
    func addRecentFolder(_ path: String) {
        let p = path.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        var list = recentFolders().filter { $0.caseInsensitiveCompare(p) != .orderedSame }
        list.insert(p, at: 0)
        while list.count > Prefs.maxRecentFolders { list.removeLast() }
        put(K.recentFolders, list.joined(separator: "\n"))
    }

    var isConfigured: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !baseUrl.trimmingCharacters(in: .whitespaces).isEmpty }
    var normalizedBase: String { Prefs.normalizeBase(baseUrl) }

    /// Clears the credential and the in-flight sign-in state. installId is deliberately kept.
    func signOut() {
        apiKey = ""
        pendingVerifier = ""
        pendingState = ""
        pendingRedirect = ""
        keyExpiresAt = ""
    }

    static func normalizeBase(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return defaultBase }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
