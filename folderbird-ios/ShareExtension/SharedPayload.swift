import Foundation
import UniformTypeIdentifiers

/// One shared attachment and how to materialise it as a file.
struct SharedItem: Identifiable {
    enum Kind {
        case fileURL(String)   // a file from Files / Mail etc. — loadItem gives the URL
        case data(String)      // an image, movie or arbitrary data — loadFileRepresentation copies it out
        case text(String)      // plain text or a web link — written as a .txt note
    }
    let id = UUID()
    let provider: NSItemProvider
    let kind: Kind
    let suggestedName: String?

    /// The name shown before the bytes are loaded.
    func displayName(index: Int) -> String {
        if let n = suggestedName?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
            if case .text = kind, (n as NSString).pathExtension.isEmpty { return n + ".txt" }
            return n
        }
        if case .text = kind { return "shared_note.txt" }
        return "file \(index + 1)"
    }
}

struct SharedPayload {
    let items: [SharedItem]

    /// Every attachment the share carried, in the order the user selected them, classified by what it can give us.
    static func collect(_ providers: [NSItemProvider]) -> SharedPayload {
        var out: [SharedItem] = []
        for p in providers {
            let ids = p.registeredTypeIdentifiers
            func first(conformingTo parent: UTType) -> String? {
                ids.first { UTType($0)?.conforms(to: parent) ?? false }
            }
            let name = p.suggestedName
            if let f = first(conformingTo: .fileURL) {
                out.append(SharedItem(provider: p, kind: .fileURL(f), suggestedName: name))
            } else if let t = first(conformingTo: .text) {
                // Only honour text when nothing binary was shared by this provider.
                out.append(SharedItem(provider: p, kind: .text(t), suggestedName: name))
            } else if let u = first(conformingTo: .url) {
                out.append(SharedItem(provider: p, kind: .text(u), suggestedName: name))
            } else if let d = first(conformingTo: .data) {
                out.append(SharedItem(provider: p, kind: .data(d), suggestedName: name))
            }
        }
        // As on Android: text is honoured only when nothing binary was shared (some apps attach a caption to a
        // photo), and at most one note is sent.
        let hasBinary = out.contains { if case .text = $0.kind { return false } else { return true } }
        if hasBinary {
            out.removeAll { if case .text = $0.kind { return true } else { return false } }
        } else if out.count > 1 {
            out = [out[0]]
        }
        return SharedPayload(items: out)
    }
}

/// Copies ONE shared item into `dir` right before upload, so the bytes always exist (and a 30-photo share
/// doesn't fill the cache before the user has even picked a folder). Returns (file, name).
enum ShareStaging {
    static func stage(_ item: SharedItem, into dir: URL) async throws -> (URL, String) {
        switch item.kind {
        case .fileURL(let type):
            let src = try await item.provider.loadURL(type: type)
            return try copyFile(src, item: item, into: dir)

        case .data(let type):
            let copied = try await item.provider.loadFileCopy(type: type, into: dir)
            var name = cleanName(item.suggestedName) ?? copied.lastPathComponent
            // A suggested name without an extension gets the loaded file's one ("IMG_0042" -> "IMG_0042.jpeg").
            if (name as NSString).pathExtension.isEmpty, !(copied.pathExtension.isEmpty) { name += "." + copied.pathExtension }
            let dest = dir.appendingPathComponent(name)
            if dest != copied {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: copied, to: dest)
            }
            try verify(dest)
            return (dest, name)

        case .text(let type):
            // A text-typed DOCUMENT (a .txt / .csv / .json from Mail or Files) arrives as a file URL under a
            // text UTI: upload its bytes, never the URL string.
            let raw = try await item.provider.loadRaw(type: type)
            if let u = raw as? URL, u.isFileURL { return try copyFile(u, item: item, into: dir) }
            let text = NSItemProvider.textValue(raw) ?? ""
            guard !text.isEmpty else { throw ApiError.message("Nothing was shared.") }
            var name = cleanName(item.suggestedName) ?? "shared_note.txt"
            if (name as NSString).pathExtension.isEmpty { name += ".txt" }
            let dest = dir.appendingPathComponent(name)
            try text.write(to: dest, atomically: true, encoding: .utf8)
            return (dest, name)
        }
    }

    /// Copies a shared file (a security-scoped URL) into our temp dir under its own name.
    private static func copyFile(_ src: URL, item: SharedItem, into dir: URL) throws -> (URL, String) {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let name = cleanName(item.suggestedName) ?? cleanName(src.lastPathComponent) ?? "shared_file"
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: src, to: dest)
        try verify(dest)
        return (dest, name)
    }

    private static func cleanName(_ raw: String?) -> String? {
        guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return nil }
        let leaf = PathUtil.fileName(r)
        return (leaf.isEmpty || leaf == "." || leaf == "..") ? nil : leaf
    }

    private static func verify(_ url: URL) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        if size == 0 { throw ApiError.message("The shared file couldn't be read (it was empty).") }
    }
}

extension NSItemProvider {
    private static let openFailure = "Couldn't open the shared file (permission may have expired — try sharing again)."

    func loadURL(type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            loadItem(forTypeIdentifier: type, options: nil) { item, err in
                if let u = item as? URL { cont.resume(returning: u) }
                else if let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { cont.resume(returning: u) }
                else { cont.resume(throwing: err ?? ApiError.message(NSItemProvider.openFailure)) }
            }
        }
    }

    /// loadFileRepresentation hands over a temp file that is deleted when the handler returns — copy it out first.
    func loadFileCopy(type: String, into dir: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            _ = loadFileRepresentation(forTypeIdentifier: type) { url, err in
                guard let url else { cont.resume(throwing: err ?? ApiError.message(NSItemProvider.openFailure)); return }
                do {
                    let dest = dir.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: dest)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// The raw item (a String, URL, NSAttributedString or Data) for a type identifier.
    func loadRaw(type: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { cont in
            loadItem(forTypeIdentifier: type, options: nil) { item, err in
                if let item { cont.resume(returning: item) }
                else { cont.resume(throwing: err ?? ApiError.message("Nothing was shared.")) }
            }
        }
    }

    /// Note text from a raw item: a string, a web link, rich text or UTF-8 data. File URLs are not text.
    static func textValue(_ raw: NSSecureCoding?) -> String? {
        if let s = raw as? String { return s }
        if let u = raw as? URL { return u.isFileURL ? nil : u.absoluteString }
        if let a = raw as? NSAttributedString { return a.string }
        if let d = raw as? Data { return String(data: d, encoding: .utf8) }
        return nil
    }
}
