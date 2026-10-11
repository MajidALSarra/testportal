import Foundation

/// The file the preview just pulled, kept on disk so Open, Save and the full viewer don't fetch it again.
///
/// This matters more here than in a normal app: there is NO server-side thumbnailing, so previewing a photo
/// downloads the WHOLE original and every fetch is a complete PC → Blob → server → phone staging round trip.
///
/// Holds ONE entry, and the key lives in memory only: after the process restarts nothing is reused, so a file
/// that changed on the PC meanwhile can never be served from a stale copy. `clear()` drops it when we
/// ourselves change the file on the PC (a text edit, an upload over the same name) or on an explicit refresh.
final class PreviewCache {
    static let shared = PreviewCache()

    /// Long enough for look-then-keep, short enough that a file edited on the PC can't be served from here for long.
    private let ttl: TimeInterval = 10 * 60
    private let lock = NSLock()
    private var key: String?
    private var file: URL?
    private var at = Date.distantPast

    private var dir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("preview", isDirectory: true)
    }

    private func keyOf(_ deviceId: String, _ fullPath: String) -> String { deviceId + "|" + fullPath.lowercased() }

    private func safeName(_ name: String) -> String {
        let n = PathUtil.fileName(name).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "file" : n
    }

    /// A destination to stream a download into; becomes the entry once `commit` confirms it landed.
    func stage(fileName: String) -> URL {
        lock.lock(); defer { lock.unlock() }
        let d = dir
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        // One entry at a time. Also sweep anything left over from an earlier session.
        let stale = Date().addingTimeInterval(-60 * 60)
        if let items = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for item in items where item != file {
                let mod = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if mod < stale { try? FileManager.default.removeItem(at: item) }
            }
        }
        if let f = file { try? FileManager.default.removeItem(at: f.deletingLastPathComponent()) }
        key = nil; file = nil
        // A per-fetch directory: two previews of same-named files (or an abandoned one) never share a path.
        let sub = d.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        return sub.appendingPathComponent(safeName(fileName))
    }

    func commit(deviceId: String, fullPath: String, url: URL) {
        lock.lock(); defer { lock.unlock() }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        if size > 0 { key = keyOf(deviceId, fullPath); file = url; at = Date() }
    }

    /// Our copy of this exact file, or nil if we don't have a fresh one.
    func get(deviceId: String, fullPath: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard key == keyOf(deviceId, fullPath), let f = file else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? NSNumber)?.int64Value ?? 0
        if size == 0 || Date().timeIntervalSince(at) > ttl {
            try? FileManager.default.removeItem(at: f.deletingLastPathComponent())
            key = nil; file = nil
            return nil
        }
        return f
    }

    /// Forget the entry — after anything that changes the file on the PC, or an explicit refresh.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        if let f = file { try? FileManager.default.removeItem(at: f.deletingLastPathComponent()) }
        key = nil; file = nil; at = .distantPast
    }

    /// Download `fullPath` into the cache (or reuse the cached copy) and return the local file.
    func fetch(api: Api, deviceId: String, fullPath: String, fileName: String,
               progress: (@MainActor (Double?) -> Void)? = nil) async throws -> URL {
        if let cached = get(deviceId: deviceId, fullPath: fullPath) { return cached }
        let out = stage(fileName: fileName)
        try await Transfers.download(api: api, deviceId: deviceId, path: fullPath, to: out, progress: progress)
        commit(deviceId: deviceId, fullPath: fullPath, url: out)
        return out
    }
}
