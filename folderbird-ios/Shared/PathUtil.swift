import Foundation

/// A file on a device: its full path plus the display name.
struct FileRef: Hashable, Identifiable {
    let path: String
    let name: String
    var id: String { path }
}

/// Windows devices use backslashes; the Linux agent's paths use forward slashes. Every helper here keeps
/// whichever separator the path itself uses, or tapping a file on a Linux device would build
/// "/root/test\file.txt" and every download/preview 404s.
enum PathUtil {
    static func isPosix(_ path: String) -> Bool { path.contains("/") && !path.contains("\\") }

    static func join(_ folder: String, _ name: String) -> String {
        let sep = isPosix(folder) ? "/" : "\\"
        var f = folder
        while f.hasSuffix("/") || f.hasSuffix("\\") { f.removeLast() }
        if f.isEmpty && sep == "/" { return "/" + name }   // directly under the POSIX root
        return f + sep + name
    }

    /// Parent of a path, or nil at a root. C:\Users\Me → C:\Users ; C:\Users → C:\ ; C:\ → nil ; /root/x → /root ; /root → / ; / → nil
    static func parent(of path: String) -> String? {
        let p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("/") {
            var t = p
            while t.count > 1 && t.hasSuffix("/") { t.removeLast() }
            if t == "/" { return nil }
            guard let i = t.lastIndex(of: "/") else { return nil }
            let parent = String(t[..<i])
            return parent.isEmpty ? "/" : parent
        }
        var t = p
        while t.hasSuffix("\\") { t.removeLast() }
        if t.count <= 2 { return nil }
        guard let i = t.lastIndex(of: "\\") else { return nil }
        let parent = String(t[..<i])
        return (parent.count == 2 && parent.hasSuffix(":")) ? parent + "\\" : parent
    }

    struct Crumb: Identifiable, Hashable {
        let id: Int
        let label: String
        let target: String
    }

    /// Breadcrumb segments after the "This PC" root: C: › Users › Me (targets C:\, C:\Users, C:\Users\Me) or
    /// / › root › test for a Linux device.
    static func crumbs(_ path: String) -> [Crumb] {
        var out: [Crumb] = []
        if path.hasPrefix("/") {
            out.append(Crumb(id: 0, label: "/", target: "/"))
            var acc = ""
            for seg in path.split(separator: "/").map(String.init) where !seg.isEmpty {
                acc += "/" + seg
                out.append(Crumb(id: out.count, label: seg, target: acc))
            }
            return out
        }
        var acc = ""
        for seg in path.split(separator: "\\").map(String.init) where !seg.isEmpty {
            acc = acc.isEmpty ? seg + "\\" : trimmedTrailing(acc) + "\\" + seg
            out.append(Crumb(id: out.count, label: seg, target: acc))
        }
        return out
    }

    private static func trimmedTrailing(_ s: String) -> String {
        var t = s
        while t.hasSuffix("\\") || t.hasSuffix("/") { t.removeLast() }
        return t
    }

    /// Last path component, whichever separator the path uses.
    static func fileName(_ path: String) -> String {
        let t = trimmedTrailing(path)
        if let i = t.lastIndex(where: { $0 == "\\" || $0 == "/" }) { return String(t[t.index(after: i)...]) }
        return t
    }

    /// Everything before the last separator (the containing folder of a search hit); the drive root keeps its separator.
    static func folder(of path: String) -> String {
        let t = trimmedTrailing(path)
        guard let i = t.lastIndex(where: { $0 == "\\" || $0 == "/" }) else { return t }
        let head = String(t[..<i])
        if head.isEmpty { return t.hasPrefix("/") ? "/" : t }
        if head.count == 2 && head.hasSuffix(":") { return head + "\\" }
        return head
    }

    /// A compact label for a recent-folder chip: the last segment with the drive as a hint, e.g. "Downloads · C:".
    static func shortFolderLabel(_ path: String) -> String {
        let p = trimmedTrailing(path)
        let leaf = fileName(p).isEmpty ? p : fileName(p)
        let drive = p.count >= 2 && Array(p)[1] == ":" ? String(p.prefix(2)) : nil
        if let d = drive, leaf.caseInsensitiveCompare(p) != .orderedSame, leaf != d { return "\(leaf) · \(d)" }
        return leaf
    }

    static func normalizeRoot(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "\\")
        if s.isEmpty { return "" }
        if s.range(of: "^[A-Za-z]:$", options: .regularExpression) != nil { s += "\\" }
        return s
    }
}

func humanSize(_ bytes: Int64?) -> String {
    guard let b = bytes else { return "" }
    if b < 1024 { return "\(b) B" }
    let kb = Double(b) / 1024
    if kb < 1024 { return String(format: "%.1f KB", kb) }
    let mb = kb / 1024
    if mb < 1024 { return String(format: "%.1f MB", mb) }
    return String(format: "%.2f GB", mb / 1024)
}

func fmtGb(_ g: Double?) -> String {
    guard let g else { return "?" }
    return g >= 1024 ? String(format: "%.1f TB", g / 1024) : String(format: "%.0f GB", g)
}

func fileMeta(_ f: FileItem) -> String {
    var parts: [String] = []
    let s = humanSize(f.size)
    if !s.isEmpty { parts.append(s) }
    if let m = f.lastmodified?.trimmingCharacters(in: .whitespaces), !m.isEmpty { parts.append(m) }
    return parts.joined(separator: " · ")
}
