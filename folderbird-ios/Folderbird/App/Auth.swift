import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

/// PKCE helpers (RFC 7636, S256) — same construction as the Android Pkce object.
enum Pkce {
    static func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static func random(_ count: Int) -> Data {
        var d = Data(count: count)
        let ok = d.withUnsafeMutableBytes { buf -> Bool in
            guard let p = buf.baseAddress else { return false }
            return SecRandomCopyBytes(kSecRandomDefault, count, p) == errSecSuccess
        }
        if !ok { d = Data((0..<count).map { _ in UInt8.random(in: 0...255) }) }
        return d
    }
    static func newVerifier() -> String { b64url(random(48)) }
    static func newState() -> String { b64url(random(16)) }
    static func challenge(_ verifier: String) -> String { b64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }
}

/// "Sign in with Folderbird": open the website's /app/authorize (PKCE) in an ASWebAuthenticationSession, then
/// exchange the returned one-time code at /app/token for a scoped API key. The redirect comes back to
/// folderbird://auth — the exact value the server allowlists for the mobile apps.
enum AuthManager {
    static let customRedirect = "folderbird://auth"
    static func redirectUri(_ prefs: Prefs) -> String { customRedirect }

    @MainActor private static var live: (session: ASWebAuthenticationSession, presenter: Presenter)?

    /// Runs the browser round trip and the code exchange. Returns the new API key (not yet stored).
    @MainActor
    static func signIn(prefs: Prefs) async throws -> String {
        // A second tap must not replace the in-flight session (and its PKCE state) with a new one.
        guard live == nil else { throw ApiError.message("A sign-in is already in progress.") }
        // Cleared on EVERY exit: a Cancel on the browser sheet throws out of the continuation below, and leaving
        // the finished pair in `live` would refuse every later sign-in until the app was killed.
        defer { live = nil }
        let verifier = Pkce.newVerifier()
        let state = Pkce.newState()
        let redirect = redirectUri(prefs)
        prefs.pendingVerifier = verifier
        prefs.pendingState = state
        prefs.pendingRedirect = redirect

        guard var comps = URLComponents(string: prefs.normalizedBase + "/app/authorize") else {
            throw ApiError.message("Bad server URL")
        }
        comps.queryItems = [
            URLQueryItem(name: "code_challenge", value: Pkce.challenge(verifier)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: redirect),
        ]
        guard let url = comps.url else { throw ApiError.message("Bad server URL") }

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "folderbird") { cb, err in
                if let cb { cont.resume(returning: cb); return }
                if let e = err as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    cont.resume(throwing: ApiError.message("Sign-in was cancelled."))
                } else {
                    cont.resume(throwing: err ?? ApiError.message("Sign-in was cancelled."))
                }
            }
            // Reuse the website's cookies so a user already signed in on this device only sees the consent page.
            session.prefersEphemeralWebBrowserSession = false
            let presenter = Presenter()
            session.presentationContextProvider = presenter
            live = (session, presenter)
            if !session.start() {
                live = nil
                cont.resume(throwing: ApiError.message("Couldn't open the sign-in page."))
            }
        }
        return try await handleCallback(prefs: prefs, url: callback)
    }

    /// Both the custom-scheme redirect and a Cancel on the consent page land here (?code=&state=, or
    /// ?error=access_denied with no code).
    static func handleCallback(prefs: Prefs, url: URL) async throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw ApiError.message("Sign-in was cancelled.")
        }
        let state = items.first(where: { $0.name == "state" })?.value ?? ""
        return try await exchange(prefs: prefs, code: code, state: state)
    }

    /// Exchange the code (from the redirect) for an API key. Verifies state, POSTs to /app/token.
    static func exchange(prefs: Prefs, code: String, state: String) async throws -> String {
        if !prefs.pendingState.isEmpty && state != prefs.pendingState {
            throw ApiError.message("Sign-in state mismatch — please try again.")
        }
        let verifier = prefs.pendingVerifier
        guard !verifier.isEmpty else { throw ApiError.message("Sign-in session expired — please try again.") }

        let redirect = prefs.pendingRedirect.isEmpty ? customRedirect : prefs.pendingRedirect
        let body: [String: Any] = [
            "code": code,
            "code_verifier": verifier,
            // The server binds the code to the redirect_uri it was minted for and requires it again here.
            "redirect_uri": redirect,
            "client": "ios",
            // Shows on Manage -> API keys, e.g. "Folderbird iOS · Apple iPad · iPad14,5 · 2026-10-06".
            "device_name": deviceName,
            // Lets the server retire THIS install's previous key only (a second device keeps its own).
            "install_id": prefs.installId,
        ]
        guard let url = URL(string: prefs.normalizedBase + "/app/token") else { throw ApiError.message("Bad server URL") }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await Api.session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200...299).contains(status) else {
            let msg = (obj["error"] as? String) ?? ""
            throw ApiError.message(msg.isEmpty ? "Sign-in failed (HTTP \(status))" : msg)
        }
        guard let key = obj["api_key"] as? String, !key.isEmpty else { throw ApiError.message("Sign-in returned no key.") }
        prefs.keyExpiresAt = (obj["expires_at"] as? String) ?? ""
        prefs.pendingVerifier = ""
        prefs.pendingState = ""
        prefs.pendingRedirect = ""
        return key
    }

    /// Best-effort server-side sign-out: POST /app/revoke with the key as bearer. Every failure is ignored —
    /// the local sign-out already happened and must never wait on the network.
    static func revokeAsync(baseUrl: String, key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, let url = URL(string: Prefs.normalizeBase(baseUrl) + "/app/revoke") else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization")
        let request = req
        Task.detached { _ = try? await Api.session.data(for: request) }
    }

    private static var deviceName: String {
        var sys = utsname()
        uname(&sys)
        let machine = withUnsafePointer(to: &sys.machine) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }
        return "Apple \(UIDevice.current.model) · \(machine)"
    }

    /// Presentation anchor for the sign-in sheet: the foreground window of this scene. The delegate is called on
    /// the main thread; assumeIsolated lets it reach UIApplication (main-actor) from this nonisolated method.
    private final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
                return active?.keyWindow ?? active?.windows.first ?? ASPresentationAnchor()
            }
        }
    }
}
