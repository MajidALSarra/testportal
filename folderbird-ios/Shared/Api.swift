import Foundation
import Combine

// ── API models (match /api/v1 responses; mirror the Android Api.kt) ──────────
// Decoding is lenient on purpose: the agent on the PC produces these payloads and a number may arrive as a
// string (or vice versa) on some builds. Moshi on Android tolerates the same shapes.

extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int64.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? "true" : "false" }
        return nil
    }
    func lenientInt64(_ key: Key) -> Int64? {
        if let i = try? decodeIfPresent(Int64.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int64(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int64(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
    func lenientBool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return ["true", "1", "yes"].contains(s.lowercased()) }
        return nil
    }
}

struct Device: Decodable, Identifiable, Hashable {
    var deviceId: Int64?
    var name: String?
    var status: String?
    var lastSeen: String?
    var appVersion: String?

    enum CodingKeys: String, CodingKey { case id, name, status, lastSeen, appVersion }

    init(deviceId: Int64? = nil, name: String? = nil, status: String? = nil, lastSeen: String? = nil, appVersion: String? = nil) {
        self.deviceId = deviceId; self.name = name; self.status = status; self.lastSeen = lastSeen; self.appVersion = appVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = c.lenientInt64(.id)
        name = c.lenientString(.name)
        status = c.lenientString(.status)
        lastSeen = c.lenientString(.lastSeen)
        appVersion = c.lenientString(.appVersion)
    }

    var id: String { idStr }
    var idStr: String { deviceId.map { String($0) } ?? "" }
    var displayName: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Device \(idStr)" : n
    }
    private var normStatus: String { (status ?? "").trimmingCharacters(in: .whitespaces).lowercased() }
    // The server reports connection HEALTH (online | slow | veryslow | offline), and treats anything that
    // isn't "offline" as reachable. Mirror that: a "slow" device is still online (just laggy).
    var isOnline: Bool { let s = normStatus; return !s.isEmpty && s != "offline" && s != "unknown" }
    var isSlow: Bool { normStatus == "slow" || normStatus == "veryslow" }
    /// Short human label for the row, e.g. "online", "online · slow connection", "offline".
    var statusLabel: String {
        switch normStatus {
        case "online": return "online"
        case "slow": return "online · slow connection"
        case "veryslow": return "online · very slow connection"
        case "", "offline": return "offline"
        default: return (status ?? "").trimmingCharacters(in: .whitespaces)
        }
    }
}

struct DevicesResponse: Decodable { var devices: [Device]? }

struct FolderItem: Decodable, Hashable {
    var name: String?
    var path: String?
    enum CodingKeys: String, CodingKey { case name, path }
    init(name: String?, path: String?) { self.name = name; self.path = path }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenientString(.name); path = c.lenientString(.path)
    }
}

struct FileItem: Decodable, Hashable {
    var name: String?
    var size: Int64?
    var lastmodified: String?
    enum CodingKeys: String, CodingKey { case name, size, lastmodified }
    init(name: String?, size: Int64?, lastmodified: String?) { self.name = name; self.size = size; self.lastmodified = lastmodified }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenientString(.name); size = c.lenientInt64(.size); lastmodified = c.lenientString(.lastmodified)
    }
}

struct FilesResponse: Decodable {
    var device: String?
    var path: String?
    var folders: [FolderItem] = []
    var files: [FileItem] = []
    enum CodingKeys: String, CodingKey { case device, path, folders, files }
    init(device: String? = nil, path: String? = nil, folders: [FolderItem] = [], files: [FileItem] = []) {
        self.device = device; self.path = path; self.folders = folders; self.files = files
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = c.lenientString(.device)
        path = c.lenientString(.path)
        // The server passes `files` through from the agent; when that payload isn't valid JSON it is a string.
        folders = (try? c.decodeIfPresent([FolderItem].self, forKey: .folders)) ?? []
        files = (try? c.decodeIfPresent([FileItem].self, forKey: .files)) ?? []
    }
}

struct SearchResult: Decodable, Hashable, Identifiable {
    var path: String?
    var size: Int64?
    var modified: String?
    enum CodingKeys: String, CodingKey { case path, size, modified }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = c.lenientString(.path); size = c.lenientInt64(.size); modified = c.lenientString(.modified)
    }
    var id: String { path ?? "" }
    var name: String { PathUtil.fileName(path ?? "") }
    var folder: String { PathUtil.folder(of: path ?? "") }
}

struct SearchResponse: Decodable {
    var count: Int = 0
    var results: [SearchResult] = []
    enum CodingKeys: String, CodingKey { case count, results }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = Int(c.lenientInt64(.count) ?? 0)
        results = (try? c.decodeIfPresent([SearchResult].self, forKey: .results)) ?? []
    }
}

struct Disk: Decodable, Hashable, Identifiable {
    var drive: String?
    var freeGB: Double?
    var totalGB: Double?
    enum CodingKeys: String, CodingKey { case drive, freeGB, totalGB }
    init(drive: String?, freeGB: Double? = nil, totalGB: Double? = nil) { self.drive = drive; self.freeGB = freeGB; self.totalGB = totalGB }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drive = c.lenientString(.drive); freeGB = c.lenientDouble(.freeGB); totalGB = c.lenientDouble(.totalGB)
    }
    var id: String { drive ?? "" }
    /// "C:" for a Windows drive; "/" for a POSIX mount.
    var letter: String {
        var s = (drive ?? "").trimmingCharacters(in: .whitespaces)
        while s.count > 1 && s.hasSuffix("\\") { s.removeLast() }
        return s
    }
    /// The path to browse when the drive is tapped: "C:\" or "/".
    var root: String { letter.hasSuffix(":") ? letter + "\\" : letter }
    var title: String { letter.isEmpty ? "Drive" : (letter.hasPrefix("/") ? "Volume (\(letter))" : "Local Disk (\(letter))") }
}

struct SystemInfo: Decodable {
    var host: String?
    var home: String?
    var disks: [Disk] = []
    enum CodingKeys: String, CodingKey { case host, home, disks }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = c.lenientString(.host); home = c.lenientString(.home)
        disks = (try? c.decodeIfPresent([Disk].self, forKey: .disks)) ?? []
    }
}

/// POST /files/preview stages the file and returns a tokenized page that renders it (Office formats etc.).
struct PreviewLink: Decodable {
    var file: String?
    var size: Int64?
    var preview_url: String?
    var download_url: String?
    var expires: String?
    enum CodingKeys: String, CodingKey { case file, size, preview_url, download_url, expires }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = c.lenientString(.file); size = c.lenientInt64(.size)
        preview_url = c.lenientString(.preview_url); download_url = c.lenientString(.download_url); expires = c.lenientString(.expires)
    }
}

/// POST /devices/code — one-time device-enrollment code (10-min TTL). required=false means this account has no
/// two-factor sign-in, so the PC will never ask for a code. Absent (older server) is treated as required.
struct DeviceCodeResponse: Decodable {
    var code: String?
    var minutes: Int?
    var required: Bool?
    enum CodingKeys: String, CodingKey { case code, minutes, required }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lenientString(.code); minutes = c.lenientInt64(.minutes).map { Int($0) }; required = c.lenientBool(.required)
    }
}

struct ExecResponse: Decodable {
    var device: String?
    var shell: String?
    var command: String?
    var output: String?
    enum CodingKeys: String, CodingKey { case device, shell, command, output }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = c.lenientString(.device); shell = c.lenientString(.shell); command = c.lenientString(.command); output = c.lenientString(.output)
    }
}

// ── Errors ───────────────────────────────────────────────────────────────────

enum ApiError: Error, LocalizedError {
    /// A non-2xx answer: the status, the API's `{ "error": "…" }` text and its machine-readable `code` when present.
    case http(status: Int, error: String?, code: String?)
    case message(String)

    var status: Int? { if case .http(let s, _, _) = self { return s }; return nil }
    var serverCode: String? { if case .http(_, _, let c) = self { return c }; return nil }
    var serverError: String? { if case .http(_, let e, _) = self { return e }; return nil }

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .http(let status, let error, _):
            if let e = error, !e.isEmpty { return "\(e) (HTTP \(status))" }
            switch status {
            case 401: return "Unauthorized — please sign in again (HTTP 401)"
            case 403: return "Access not allowed for this key (HTTP 403)"
            case 504: return "The device didn't respond in time (HTTP 504)"
            default: return "HTTP \(status)"
            }
        }
    }
}

/// Human-readable message from any error, unwrapping the API's { "error": "…" } bodies and HTTP codes.
func errorMessage(_ error: Error) -> String {
    if let a = error as? ApiError { return a.errorDescription ?? "Error" }
    if let u = error as? URLError {
        switch u.code {
        case .timedOut: return "The request timed out — the device may be offline or busy."
        case .notConnectedToInternet: return "No internet connection."
        case .cancelled: return "Cancelled."
        default: return u.localizedDescription
        }
    }
    let d = (error as NSError).localizedDescription
    return d.isEmpty ? String(describing: error) : d
}

/// Raised when the server rejects the stored key (HTTP 401 = invalid, expired or revoked). The root view
/// collects it and drops to the sign-in screen. 403 is a missing SCOPE on a live key and keeps its own messages.
final class AuthState: ObservableObject {
    static let shared = AuthState()
    @Published var expired = false
    func onUnauthorized() { DispatchQueue.main.async { self.expired = true } }
}

// ── Client ───────────────────────────────────────────────────────────────────

/// A thin async client for /api/v1, built from the current settings. Cheap to recreate whenever settings change.
struct Api {
    let base: String
    let key: String

    init(_ prefs: Prefs) {
        base = prefs.normalizedBase
        key = prefs.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    init(base: String, key: String) { self.base = Prefs.normalizeBase(base); self.key = key }

    /// Browse waits up to 30s and uploads up to 120s on the server — give generous timeouts.
    static let config: URLSessionConfiguration = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 150
        c.timeoutIntervalForResource = 60 * 60
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        return c
    }()
    static let session = URLSession(configuration: config)

    /// Strict percent-encoding for query values: only unreserved characters pass through, so a "+" or "&" in a
    /// file name reaches ASP.NET Core as itself (a bare "+" would decode as a space).
    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    func request(_ path: String, query: [(String, String)] = [], method: String = "GET",
                 body: Data? = nil, contentType: String? = nil) throws -> URLRequest {
        var urlString = base + path
        if !query.isEmpty {
            urlString += "?" + query.map { "\($0.0)=\(Api.encode($0.1))" }.joined(separator: "&")
        }
        guard let url = URL(string: urlString) else { throw ApiError.message("Bad server URL") }
        var r = URLRequest(url: url, timeoutInterval: 150)
        r.httpMethod = method
        if !key.isEmpty { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ct = contentType { r.setValue(ct, forHTTPHeaderField: "Content-Type") }
        r.httpBody = body
        return r
    }

    /// Turns a non-2xx answer into an ApiError (parsing { error, code }) and reports a 401 so the UI can
    /// drop to the sign-in screen — exactly what the Android OkHttp interceptor does.
    static func httpError(status: Int, body: Data, hadKey: Bool) -> ApiError {
        var err: String?
        var code: String?
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            err = obj["error"] as? String
            code = obj["code"] as? String
        }
        if status == 401 && hadKey { AuthState.shared.onUnauthorized() }
        return .http(status: status, error: err, code: code)
    }

    private func check(_ data: Data, _ resp: URLResponse) throws -> Data {
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw Api.httpError(status: status, body: data, hadKey: !key.isEmpty) }
        return data
    }

    private func run<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await Api.session.data(for: req)
        let ok = try check(data, resp)
        do { return try JSONDecoder().decode(T.self, from: ok) }
        catch { throw ApiError.message("Unexpected answer from the server.") }
    }

    @discardableResult
    private func runRaw(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await Api.session.data(for: req)
        return try check(data, resp)
    }

    private func devicePath(_ id: String, _ rest: String) -> String { "/api/v1/devices/\(Api.encode(id))\(rest)" }

    // ── Endpoints ──

    func devices() async throws -> [Device] {
        let r: DevicesResponse = try await run(try request("/api/v1/devices"))
        return r.devices ?? []
    }

    func deviceCode() async throws -> DeviceCodeResponse {
        try await run(try request("/api/v1/devices/code", method: "POST"))
    }

    /// Run a console command on the PC. shell is "cmd" or "powershell"; the server waits up to ~45s for the device.
    /// confirmDestructive: a command the server classes as destructive (del, rm, Remove-Item, format, shutdown, …)
    /// is refused with 409 { error, code: "confirm_destructive_required" } unless this is true. Leave it nil on a
    /// first attempt and set it only after the user confirmed in the console — never unconditionally.
    func exec(_ id: String, command: String, shell: String, confirmDestructive: Bool? = nil) async throws -> ExecResponse {
        var obj: [String: Any] = ["command": command, "shell": shell]
        if let c = confirmDestructive { obj["confirmDestructive"] = c }
        let body = try JSONSerialization.data(withJSONObject: obj)
        return try await run(try request(devicePath(id, "/exec"), method: "POST", body: body, contentType: "application/json"))
    }

    func files(_ id: String, path: String) async throws -> FilesResponse {
        try await run(try request(devicePath(id, "/files"), query: [("path", path)]))
    }

    func system(_ id: String) async throws -> SystemInfo {
        try await run(try request(devicePath(id, "/system")))
    }

    func search(_ id: String, q: String, scope: String?, content: Bool) async throws -> SearchResponse {
        var query = [("q", q)]
        if let s = scope, !s.isEmpty { query.append(("scope", s)) }
        query.append(("content", content ? "true" : "false"))
        return try await run(try request(devicePath(id, "/search"), query: query))
    }

    func previewLink(_ id: String, path: String) async throws -> PreviewLink {
        try await run(try request(devicePath(id, "/files/preview"), query: [("path", path)], method: "POST"))
    }

    func createFolder(_ id: String, path: String) async throws {
        try await runRaw(try request(devicePath(id, "/folders"), query: [("path", path)], method: "POST"))
    }

    func writeText(_ id: String, path: String, content: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["content": content])
        try await runRaw(try request(devicePath(id, "/files/write"), query: [("path", path)], method: "POST", body: body, contentType: "application/json"))
    }

    /// Resolve the device's home folder (e.g. C:\Users\Majid). Prefers the server-provided USERPROFILE (or a
    /// POSIX home from the Linux agent), otherwise picks the single real profile under C:\Users. nil if it
    /// can't tell, in which case the caller lands on "This PC" (the drive list) instead.
    /// Share flow (Android ShareActivity.resolveHomeFolder): fetches /system itself.
    func resolveHomeFolder(_ id: String) async -> String? {
        let info = try? await system(id)
        return await resolveHomeFolder(id, system: info)
    }

    /// Browse flow (Android MainActivity.resolveHomeFolder): uses the /system answer the caller already has and
    /// never requests it again — an offline device would otherwise wait out the timeout twice.
    func resolveHomeFolder(_ id: String, system info: SystemInfo?) async -> String? {
        if let h = info?.home?.trimmingCharacters(in: .whitespaces) {
            let chars = Array(h)
            if chars.count >= 3 && chars[1] == ":" { return h }
            if h.hasPrefix("/") && h.count > 1 { return h }
        }
        let systemProfiles: Set<String> = ["public", "default", "default user", "all users", "defaultuser0", "wdagutilityaccount"]
        guard let users = try? await files(id, path: "C:\\Users") else { return nil }
        let real = users.folders.compactMap { $0.path }.filter { p in
            let n = PathUtil.fileName(p).lowercased()
            return !n.isEmpty && !n.hasPrefix(".") && !systemProfiles.contains(n)
        }
        return real.count == 1 ? real[0] : nil
    }
}
