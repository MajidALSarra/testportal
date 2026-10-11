import SwiftUI

// Brand palette (matches the website logo / CSS and the Android FbTheme in Support.kt).
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum FB {
    static let blue = Color(hex: 0x0D6EFD)
    static let blueDark = Color(hex: 0x4F9BFF)
    /// Device-status colours: green online, amber laggy, grey offline (the symbols alone read as one grey wall).
    static let online = Color(hex: 0x1F9D4D)
    static let slow = Color(hex: 0xE08A1E)
    static let success = Color(hex: 0x2FA86A)
    /// The console keeps a fixed dark terminal look in both themes — that's what a console is.
    static let terminalBg = Color(hex: 0x0D1117)
    static let terminalDim = Color(hex: 0x8B949E)
    static let terminalPrompt = Color(hex: 0x58A6FF)
    static let terminalText = Color(hex: 0xC9D1D9)
    static let terminalError = Color(hex: 0xFF7B72)

    // ── Folder icons — mirror the website's special-folder set (fbFolderIcon) ──
    private static func norm(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Special-folder icon matching the website: desktop / documents / downloads / pictures; else a plain folder.
    static func folderIcon(_ name: String) -> String {
        switch norm(name) {
        case "desktop": return "desktopcomputer"
        case "documents", "my documents": return "doc.text.fill"
        case "downloads": return "arrow.down.circle.fill"
        case "pictures", "my pictures": return "photo.fill"
        default: return "folder.fill"
        }
    }

    /// Matching accent colour for the special folders (same hex as the website); nil → the default folder tint.
    static func folderTint(_ name: String) -> Color? {
        switch norm(name) {
        case "desktop": return Color(hex: 0x5B7FDB)
        case "documents", "my documents": return Color(hex: 0x4A90D9)
        case "downloads": return Color(hex: 0x2FA86A)
        case "pictures", "my pictures": return Color(hex: 0xD97A4A)
        default: return nil
        }
    }

    /// Rank used to pin the website's special folders to the top of a listing.
    static func folderRank(_ name: String) -> Int {
        switch norm(name) {
        case "desktop": return 0
        case "documents", "my documents": return 1
        case "downloads": return 2
        case "pictures", "my pictures": return 3
        default: return Int.max
        }
    }

    // ── File types ──
    static let textExts: Set<String> = ["txt", "md", "markdown", "json", "xml", "csv", "tsv", "log", "ini", "cfg", "conf", "config",
        "yml", "yaml", "html", "htm", "js", "ts", "css", "kt", "java", "cs", "c", "cpp", "h", "py", "rb", "go", "rs", "php", "sh", "bat",
        "ps1", "sql", "gradle", "properties", "env", "gitignore", "toml", "srt", "vtt", "swift"]
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "heif", "tif", "tiff", "jfif"]
    // Office formats render on the server's tokenized /preview page (the same PPTXjs / docx-preview / SheetJS
    // stack the website uses) inside a web view — no renderer to bundle or keep in step here.
    static let officeExts: Set<String> = ["pptx", "docx", "xlsx", "xls"]

    static func ext(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }
    static func isText(_ name: String) -> Bool { textExts.contains(ext(name)) }
    static func isImage(_ name: String) -> Bool { imageExts.contains(ext(name)) }
    static func isOffice(_ name: String) -> Bool { officeExts.contains(ext(name)) }
    static func isPdf(_ name: String) -> Bool { ext(name) == "pdf" }

    /// Icon + the file type's recognisable colour, mirroring the website's colourful file icons (Word blue,
    /// Excel green, PowerPoint orange, PDF red, amber images) instead of a wall of identical grey glyphs.
    static func fileVisual(_ name: String) -> (icon: String, tint: Color?) {
        switch ext(name) {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "heic", "heif", "tif", "tiff", "jfif":
            return ("photo", Color(hex: 0xE8963D))
        case "pdf": return ("doc.richtext", Color(hex: 0xD93025))
        case "doc", "docx", "rtf", "odt": return ("doc.text", Color(hex: 0x2B579A))
        case "xls", "xlsx", "csv", "tsv", "ods": return ("tablecells", Color(hex: 0x217346))
        case "ppt", "pptx", "odp": return ("rectangle.on.rectangle", Color(hex: 0xD24726))
        case "zip", "rar", "7z", "tar", "gz": return ("doc.zipper", Color(hex: 0x8D6E63))
        case "mp3", "wav", "m4a", "flac", "aac", "ogg": return ("music.note", Color(hex: 0x7E57C2))
        case "mp4", "mov", "mkv", "avi", "webm": return ("film", Color(hex: 0xAB47BC))
        case "txt", "md", "log", "ini", "cfg", "json", "xml", "yml", "yaml": return ("doc.plaintext", Color(hex: 0x607D8B))
        case "js", "ts", "py", "cs", "kt", "java", "html", "css", "sh", "ps1", "bat", "swift": return ("curlybraces", Color(hex: 0x00897B))
        case "exe": return ("gearshape", Color(hex: 0x78909C))
        default: return ("doc", nil)
        }
    }
}

/// Special folders first (Desktop → Documents → Downloads → Pictures), then everything else alphabetically.
func sortFolders(_ folders: [FolderItem]) -> [FolderItem] {
    folders.sorted { a, b in
        let an = a.name ?? a.path ?? "", bn = b.name ?? b.path ?? ""
        let ra = FB.folderRank(an), rb = FB.folderRank(bn)
        if ra != rb { return ra < rb }
        return an.lowercased() < bn.lowercased()
    }
}
