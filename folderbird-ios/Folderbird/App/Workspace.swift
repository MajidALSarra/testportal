import SwiftUI
import Combine
import UIKit
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

/// Where a finished "save to this device" landed, and the URL to share it from.
struct SavedDownload: Identifiable {
    let name: String
    let location: String
    let url: URL
    var id: String { url.path }
}

/// One console command and its (eventual) output. output == nil while it's still running on the PC.
struct ConsoleEntry: Identifiable, Equatable {
    var id = UUID()
    var cmd: String
    var shell: String
    var output: String?
    var error = false
}

/// The server refused a command it classes as destructive (409, code "confirm_destructive_required") and wants
/// an explicit go-ahead. idx is the history row, left "running…" until the user answers.
struct DestructiveConfirm: Identifiable {
    var id = UUID()
    let idx: Int
    let cmd: String
    let shell: String
    let error: String
}

/// The text editor's buffer, owned by the device's model so switching devices in the sidebar or resizing the
/// window across the layout boundary never loses an unsaved edit.
final class EditorDraft: ObservableObject {
    @Published var text = ""
    @Published var loadedText = ""
    /// The file the buffer belongs to; nil = empty.
    var path: String?
    var dirty: Bool { path != nil && text != loadedText }
    func reset() { path = nil; text = ""; loadedText = "" }
}

/// App-wide navigation state shared by the phone and iPad layouts, so resizing an iPad window across the
/// size-class boundary (Stage Manager, Split View) keeps the selected device, folder, preview and console.
@MainActor
final class Workspace: ObservableObject {
    @Published var devices: [Device] = []
    @Published var selectedDeviceId: String?
    private var models: [String: BrowseModel] = [:]

    var selectedDevice: Device? {
        guard let id = selectedDeviceId else { return nil }
        return devices.first { $0.idStr == id }
    }

    /// Drop everything tied to a session — called whenever the signed-in state ends (sign-out, 401, re-auth), so
    /// the next account never lands in the previous one's device browser.
    func reset() {
        devices = []
        selectedDeviceId = nil
        models.removeAll()
    }

    /// One browse model per device, kept for the life of the window.
    func model(for device: Device) -> BrowseModel {
        if let m = models[device.idStr] {
            if m.device != device { m.device = device }
            return m
        }
        let m = BrowseModel(device: device)
        models[device.idStr] = m
        return m
    }
}

/// Everything the browser screen knows about one device: the folder being shown, drives, search, the file being
/// previewed or edited, the console, and the active transfer. Mirrors the state of the Android BrowseScreen +
/// ConsoleScreen so both layouts (and both iPad columns) render from one source of truth.
@MainActor
final class BrowseModel: ObservableObject {
    var device: Device
    var deviceId: String { device.idStr }

    @Published var path: String?
    @Published var listing: FilesResponse?
    @Published var drives: [Disk]?
    @Published var loading = false
    @Published var drivesLoading = false
    @Published var error: String?
    @Published var drivesError: String?

    @Published var searchOpen = false
    @Published var query = ""
    @Published var inContent = false
    @Published var results: [SearchResult]?
    @Published var searching = false

    /// Quick preview (docked on the phone, the detail column on iPad).
    @Published var previewing: FileRef?
    /// Full-screen viewer / text editor.
    @Published var editing: FileRef?
    /// The editor's buffer (observed by the editor view only, so typing doesn't republish this model).
    let draft = EditorDraft()
    /// Unsaved edits in the open editor — the iPad table and the console button ask before replacing it.
    var editorDirty: Bool {
        guard let e = editing else { return false }
        return draft.path == e.path && draft.dirty
    }
    /// Set when the console was requested while the editor held unsaved edits; the browser shows the prompt.
    @Published var pendingConsoleDiscard = false
    @Published var consoleOpen = false
    @Published var consoleShell = "cmd"
    @Published var consoleHistory: [ConsoleEntry] = []
    @Published var consoleBusy = false
    @Published var consoleConfirm: DestructiveConfirm?
    @Published var consoleTick = 0

    @Published var xfer: Xfer?
    @Published var saved: SavedDownload?
    @Published var quickLookURL: URL?
    @Published var toast: String?

    private var landed = false
    private var loadGeneration = 0
    private var xferGeneration = 0
    private var toastGeneration = 0
    private var api: Api { Api(Prefs.shared) }

    init(device: Device) { self.device = device }

    // MARK: - Navigation

    private var landing: Task<Void, Never>?

    /// Model-owned: the landing must outlive BrowseView's `.task`, which SwiftUI cancels when the view disappears
    /// (Back on the phone, another sidebar device on iPad). A cancelled landing used to leave the device stuck on
    /// "Couldn't read the drives. Cancelled." with `landed` already true.
    func landIfNeeded() {
        guard !landed else { return }
        landed = true
        landing = Task { await self.land() }
    }

    /// On open, land on the user's home folder (like the website) — Documents, Pictures, Downloads, etc.
    /// Fall back to "This PC" (drives) if the home can't be resolved (e.g. the device is offline).
    func land() async {
        loading = true; error = nil
        // Anything the user does during the landing's round trips (a search, a folder tap) bumps the generation
        // and wins; the landing then stands down instead of yanking the view to the home folder.
        let gen = loadGeneration
        let sys = try? await api.system(deviceId)
        if Task.isCancelled { landed = false; loading = false; return }   // try again on the next appearance
        if let s = sys { drives = s.disks.filter { !($0.drive ?? "").isEmpty } }
        let home = await api.resolveHomeFolder(deviceId, system: sys)
        guard gen == loadGeneration else { return }
        if let home {
            await load(home)
        } else {
            loading = false
            if drives == nil && !drivesLoading { await loadDrives() }
            // The device never answered (no /system, no drives): nothing landed, so try again next time it opens;
            // an online device whose home merely cannot be resolved keeps its drives and is not re-asked.
            if sys == nil && drives == nil { landed = false }
        }
    }

    func loadDrives() async {
        drivesLoading = true; drivesError = nil
        do {
            let sys = try await api.system(deviceId)
            drives = sys.disks.filter { !($0.drive ?? "").isEmpty }
        } catch let e {
            if !isCancellation(e) { drivesError = errorMessage(e) }
        }
        drivesLoading = false
    }

    func load(_ p: String?) async {
        loadGeneration += 1
        let gen = loadGeneration
        path = p; error = nil; results = nil
        searching = false            // a superseded search must not leave its spinner on
        guard let p else {
            listing = nil
            loading = false
            if drives == nil && !drivesLoading { await loadDrives() }
            return
        }
        loading = true
        do {
            let r = try await api.files(deviceId, path: p)
            guard gen == loadGeneration else { return }
            listing = r
        } catch let e {
            guard gen == loadGeneration else { return }
            if isCancellation(e) { loading = false; return }   // the caller went away; keep what was on screen
            error = errorMessage(e); listing = nil
        }
        loading = false
    }

    /// Refresh means "get me the current state of the PC", so it also drops the previewed copy we're holding —
    /// the user's way to force fresh bytes for a file being edited there.
    func refresh() async {
        PreviewCache.shared.clear()
        // A clean buffer is dropped so the next open re-reads the PC — unless an editor is showing it right now
        // (on iPad the folder toolbar and ⌘R stay reachable beside the detail column, and resetting the draft
        // the TextEditor is bound to would blank it). Edits are always kept.
        if editing == nil && !draft.dirty { draft.reset() }
        if path == nil { await loadDrives() } else { await load(path) }
    }

    func goUp() async {
        guard let p = path else { return }
        await load(PathUtil.parent(of: p))
    }

    // MARK: - Search

    func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loadGeneration += 1
        let gen = loadGeneration
        loading = false              // a superseded load must not leave its spinner on
        searching = true; results = nil; error = nil
        do {
            let r = try await api.search(deviceId, q: q, scope: path, content: inContent)
            guard gen == loadGeneration else { return }
            results = r.results
        } catch let e {
            guard gen == loadGeneration else { return }
            if isCancellation(e) { searching = false; return }
            error = errorMessage(e)
        }
        searching = false
    }

    func closeSearch() {
        if searching {               // an in-flight search must not land after the bar is dismissed
            loadGeneration += 1
            searching = false
        }
        results = nil
        searchOpen = false
    }

    // MARK: - Editor / console switching

    /// Closes the editor and drops its buffer.
    func closeEditor() {
        editing = nil
        draft.reset()
    }

    /// Opens the console in the detail column (iPad) or as a pushed screen (phone). The editor gives way, but
    /// never silently: unsaved edits raise the discard prompt first.
    func openConsole() {
        if editing != nil && editorDirty {
            pendingConsoleDiscard = true
            return
        }
        if editing != nil { closeEditor() }
        consoleOpen = true
    }

    func discardAndOpenConsole() {
        pendingConsoleDiscard = false
        closeEditor()
        consoleOpen = true
    }

    /// Retry for the error box: re-run whichever request produced the error.
    func retry() async {
        if results != nil || (searchOpen && !query.trimmingCharacters(in: .whitespaces).isEmpty) { await runSearch() }
        else { await load(path) }
    }

    // MARK: - Folder ops

    func createFolder(named name: String) async {
        guard let p = path else { return }
        do {
            try await api.createFolder(deviceId, path: PathUtil.join(p, name))
            showToast("Folder created")
            await load(p)
        } catch let e {
            showToast("Create failed: \(errorMessage(e))")
        }
    }

    // MARK: - Transfers

    /// Upload picked or dropped files into the current folder, one at a time, then reload it.
    func upload(_ urls: [URL]) async {
        guard let folder = path else { return }
        var anyLanded = false
        for url in urls { if await uploadOne(url, to: folder) { anyLanded = true } }
        // Re-list only when something changed, as Android does: after a failure the listing stays on screen
        // under the red bar instead of being replaced by an error box from a second round trip.
        if anyLanded { await load(folder) }
    }

    /// Upload photos/videos picked from the Photos library (the Android picker reaches the gallery; the Files
    /// picker on iOS does not). PickedMedia has already copied each item into a temp folder of ours, so the
    /// normal upload path handles them; those folders are removed afterwards.
    func upload(picked items: [PhotosPickerItem]) async {
        guard path != nil, !items.isEmpty else { return }
        setXfer(Xfer(label: items.count == 1 ? "Reading from Photos…" : "Reading \(items.count) items from Photos…", frac: nil))
        var urls: [URL] = []
        var failed = 0
        for item in items {
            do {
                let media = try await item.loadTransferable(type: PickedMedia.self)
                if let media { urls.append(media.url) } else { failed += 1 }
            } catch {
                failed += 1
            }
        }
        defer { for u in urls { try? FileManager.default.removeItem(at: u.deletingLastPathComponent()) } }
        if urls.isEmpty {
            finishXfer(Xfer(label: items.count == 1 ? "Couldn't read that item from Photos." : "Couldn't read those items from Photos.",
                            frac: nil, done: true, error: true))
            return
        }
        await upload(urls)
        if failed > 0 {
            finishXfer(Xfer(label: "\(failed) of \(items.count) items couldn't be read from Photos.", frac: nil, done: true, error: true))
        }
    }

    /// True when the file landed on the PC.
    private func uploadOne(_ url: URL, to folder: String) async -> Bool {
        let name = url.lastPathComponent
        setXfer(Xfer(label: "Uploading \(name)", frac: 0))
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fb-pick-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            // Copy into our own sandbox first (off the main actor — an iCloud item may need downloading): a
            // picked/dropped URL is a security-scoped reference that goes away.
            let local = try await Transfers.stage(url, into: tmp, name: name)
            try await Transfers.upload(api: api, deviceId: deviceId, folder: folder, fileURL: local, fileName: name) { [weak self] f in
                // Two honest phases: the fraction tracks phone -> server bytes; once they're all sent the SERVER
                // is still delivering to the PC, so switch to an indeterminate "sending to device" state instead
                // of sitting silently at 100%.
                if f >= 1 { self?.xfer = Xfer(label: "Sending \(name) to the device…", frac: nil) }
                else { self?.xfer = Xfer(label: "Uploading \(name)", frac: f) }
            }
            // An upload can land on the same name we have cached, so drop it rather than risk showing or
            // saving the file the upload replaced.
            PreviewCache.shared.clear()
            finishXfer(Xfer(label: "Uploaded \(name)", frac: 1, done: true))
            return true
        } catch let e {
            finishXfer(Xfer(label: "Upload failed: \(errorMessage(e))", frac: nil, done: true, error: true))
            return false
        }
    }

    /// Saves into the app's Documents folder, which the Files app shows as "On My iPhone/iPad › Folderbird", then
    /// offers Share as a BUTTON (the Android app's Downloads/Folderbird + dialog behaviour).
    func saveToDevice(_ file: FileRef) async {
        // If the preview already pulled this file, Save is a local copy — no second trip to the PC.
        let cached = PreviewCache.shared.get(deviceId: deviceId, fullPath: file.path)
        let label = cached != nil ? "Saving \(file.name)" : "Downloading \(file.name)"
        setXfer(Xfer(label: label, frac: nil))
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            let dest = uniqueURL(in: docs, name: file.name)
            if let c = cached {
                try FileManager.default.copyItem(at: c, to: dest)
            } else {
                try await Transfers.download(api: api, deviceId: deviceId, path: file.path, to: dest) { [weak self] f in
                    self?.xfer = Xfer(label: label, frac: f)
                }
            }
            finishXfer(Xfer(label: "Saved \(dest.lastPathComponent)", frac: 1, done: true))
            saved = SavedDownload(name: dest.lastPathComponent,
                                  location: "Files › On My \(UIDevice.current.model) › Folderbird",
                                  url: dest)
        } catch let e {
            finishXfer(Xfer(label: "Download failed: \(errorMessage(e))", frac: nil, done: true, error: true))
            showToast("Download failed: \(errorMessage(e))")
        }
    }

    /// "Open with another app": pull the bytes (or reuse the preview's copy) and hand them to Quick Look, which
    /// previews nearly everything and offers the share sheet for the rest.
    func openExternally(_ file: FileRef) async {
        if let c = PreviewCache.shared.get(deviceId: deviceId, fullPath: file.path) { quickLookURL = c; return }
        showToast("Opening \(file.name)…")
        do {
            quickLookURL = try await PreviewCache.shared.fetch(api: api, deviceId: deviceId, fullPath: file.path, fileName: file.name)
        } catch let e {
            showToast("Open failed: \(errorMessage(e))")
        }
    }

    func setXfer(_ x: Xfer) {
        xferGeneration += 1
        xfer = x
    }

    /// Shows a finished transfer, then clears the bar a couple of seconds later (unless a newer one started).
    func finishXfer(_ x: Xfer) {
        xferGeneration += 1
        let gen = xferGeneration
        xfer = x
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, self.xferGeneration == gen else { return }
            self.xfer = nil
        }
    }

    func showToast(_ message: String) {
        toastGeneration += 1
        let gen = toastGeneration
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard let self, self.toastGeneration == gen else { return }
            self.toast = nil
        }
    }

    // MARK: - Console

    func consoleRun(_ raw: String) {
        let c = raw.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty, !consoleBusy else { return }
        let idx = consoleHistory.count
        consoleHistory.append(ConsoleEntry(cmd: c, shell: consoleShell, output: nil))
        consoleTick += 1
        let sh = consoleShell
        Task { await self.consoleSend(c, sh, idx: idx) }
    }

    /// Sends one command and settles history[idx] with its output or an error. confirmDestructive = true is sent
    /// ONLY from the confirmation dialog, never on a first attempt: the server gates destructive commands because
    /// it cannot tell the phone from an AI caller (both use API keys), so the app must really ask.
    func consoleSend(_ c: String, _ sh: String, idx: Int, confirmDestructive: Bool? = nil) async {
        consoleBusy = true
        do {
            let r = try await api.exec(deviceId, command: c, shell: sh, confirmDestructive: confirmDestructive)
            let raw = r.output ?? ""
            let out = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no output)" : raw
            setConsole(idx, ConsoleEntry(cmd: c, shell: sh, output: out))
            consoleBusy = false
        } catch let e {
            let apiErr = e as? ApiError
            if apiErr?.status == 409, apiErr?.serverCode == "confirm_destructive_required", confirmDestructive != true {
                // Row stays "running…" and the input stays busy until the dialog is answered.
                consoleConfirm = DestructiveConfirm(idx: idx, cmd: c, shell: sh,
                                                    error: apiErr?.serverError ?? "This command needs confirmation")
                return
            }
            consoleBusy = false
            let msg: String
            switch apiErr?.status {
            case 403: msg = "This sign-in is missing the console permission — sign out and back in (More → Account & settings), then try again."
            case 409: msg = "\(apiErr?.serverError ?? "Conflict") (HTTP 409)"
            case 504: msg = "The device didn't respond within 45 seconds — it may be offline or busy."
            default: msg = errorMessage(e)
            }
            setConsole(idx, ConsoleEntry(cmd: c, shell: sh, output: msg, error: true))
        }
    }

    func consoleConfirmYes(_ p: DestructiveConfirm) {
        consoleConfirm = nil
        Task { await self.consoleSend(p.cmd, p.shell, idx: p.idx, confirmDestructive: true) }
    }

    /// "No" on the confirmation: the row gets the server's refusal, formatted the way any other error is.
    func consoleDecline(_ p: DestructiveConfirm) {
        consoleConfirm = nil
        consoleBusy = false
        setConsole(p.idx, ConsoleEntry(cmd: p.cmd, shell: p.shell, output: "\(p.error) (HTTP 409)", error: true))
    }

    func consoleClear() {
        consoleHistory.removeAll()
        consoleTick += 1
    }

    private func setConsole(_ idx: Int, _ entry: ConsoleEntry) {
        guard consoleHistory.indices.contains(idx) else { return }
        var e = entry
        e.id = consoleHistory[idx].id
        consoleHistory[idx] = e
        consoleTick += 1
    }
}

/// A free file name in `dir`: "name.ext", then "name (1).ext", "name (2).ext", … so nothing is overwritten.
/// A photo or video handed over by PhotosPicker. The picker's file lives only until the import closure returns,
/// so it is copied into a private temp folder of ours first; the original name (IMG_1234.HEIC, IMG_0042.MOV) is
/// kept, which is what lands on the PC.
struct PickedMedia: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in try PickedMedia(copying: received.file) }
        FileRepresentation(importedContentType: .image) { received in try PickedMedia(copying: received.file) }
    }

    private init(copying file: URL) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fb-photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = PathUtil.fileName(file.lastPathComponent).isEmpty ? "photo" : PathUtil.fileName(file.lastPathComponent)
        let dest = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: file, to: dest)
        url = dest
    }
}

func uniqueURL(in dir: URL, name: String) -> URL {
    let fm = FileManager.default
    let clean = PathUtil.fileName(name).isEmpty ? "file" : PathUtil.fileName(name)
    var candidate = dir.appendingPathComponent(clean)
    if !fm.fileExists(atPath: candidate.path) { return candidate }
    let base = (clean as NSString).deletingPathExtension
    let ext = (clean as NSString).pathExtension
    var n = 1
    while true {
        let nm = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
        candidate = dir.appendingPathComponent(nm)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        n += 1
    }
}
