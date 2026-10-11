import SwiftUI

/// One row of the iPad file table: a folder or a file.
struct FolderEntry: Identifiable, Hashable {
    let id: String          // "d:" + path for folders, "f:" + path for files
    let name: String
    let isFolder: Bool
    let path: String
    let size: Int64?
    let modified: String
    let modifiedKey: Int64
    var sizeKey: Int64 { isFolder ? -1 : (size ?? 0) }

    /// A sortable key for the agent's "dd/MM/yyyy HH:mm:ss" stamp. The separators follow the PC's locale
    /// ("20.06.2026" on a German PC), so the six numbers are taken wherever they sit; a four-digit first
    /// number means year-first. Unparsable → Int64.min (sorts last ascending).
    static func key(forModified s: String) -> Int64 {
        let runs = s.split(whereSeparator: { !$0.isNumber }).map { String($0) }
        guard runs.count >= 3, let a = Int64(runs[0]), let b = Int64(runs[1]), let c = Int64(runs[2]) else { return Int64.min }
        let yearFirst = runs[0].count == 4
        let (year, month, day) = yearFirst ? (a, b, c) : (c, b, a)
        let hour = runs.count > 3 ? (Int64(runs[3]) ?? 0) : 0
        let minute = runs.count > 4 ? (Int64(runs[4]) ?? 0) : 0
        let second = runs.count > 5 ? (Int64(runs[5]) ?? 0) : 0
        return ((((year * 100 + month) * 100 + day) * 100 + hour) * 100 + minute) * 100 + second
    }
}

/// What a tap asked for while the editor held unsaved edits.
private struct PendingSwitch: Identifiable {
    let ref: FileRef
    let edit: Bool
    var id: String { ref.path }
}

/// iPad (regular width): a desktop-class, sortable table with Name / Size / Modified columns instead of the
/// phone's list. Tap a folder to open it, tap a file to preview it in the detail column; column headers sort;
/// right-click / long-press for the file actions; drop files from the Files app to upload them.
@MainActor
struct FolderTable: View {
    @ObservedObject var model: BrowseModel
    @State private var sortOrder: [KeyPathComparator<FolderEntry>] = [KeyPathComparator(\.name, comparator: .localizedStandard)]
    @State private var selection: String?
    @State private var pendingSwitch: PendingSwitch?

    private var entries: [FolderEntry] {
        let listing = model.listing ?? FilesResponse()
        let folders = sortFolders(listing.folders).map { f -> FolderEntry in
            let nm = f.name ?? f.path ?? ""
            return FolderEntry(id: "d:" + (f.path ?? nm), name: nm, isFolder: true, path: f.path ?? "",
                               size: nil, modified: "", modifiedKey: Int64.min)
        }
        let files = listing.files.map { file -> FolderEntry in
            let nm = (file.name ?? "").isEmpty ? "download" : (file.name ?? "")
            let full = PathUtil.join(model.path ?? "", nm)
            let mod = file.lastmodified ?? ""
            return FolderEntry(id: "f:" + full, name: nm, isFolder: false, path: full,
                               size: file.size, modified: mod, modifiedKey: FolderEntry.key(forModified: mod))
        }
        // Folders stay above files, and the website's special folders stay pinned on top (as on Android);
        // the chosen column sort applies to the rest.
        let special = folders.filter { FB.folderRank($0.name) != Int.max }
        let rest = folders.filter { FB.folderRank($0.name) == Int.max }.sorted(using: sortOrder)
        return special + rest + files.sorted(using: sortOrder)
    }

    /// The row the detail column is showing, in DetailPane's order: the editor's file; nothing while the console
    /// covers the preview (so a tap on the previewed row brings the preview back); else the preview's file.
    private var detailId: String? {
        if let e = model.editing { return "f:" + e.path }
        if model.consoleOpen { return nil }
        return model.previewing.map { "f:" + $0.path }
    }

    var body: some View {
        let rows = entries
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name, comparator: String.StandardComparator.localizedStandard) { e in
                HStack(spacing: 10) {
                    icon(e)
                    Text(e.name).fontWeight(e.isFolder ? .medium : .regular).lineLimit(1)
                }
            }
            TableColumn("Size", value: \.sizeKey) { e in
                Text(e.isFolder ? "—" : humanSize(e.size)).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 130)
            TableColumn("Modified", value: \.modifiedKey) { e in
                Text(e.modified).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 120, ideal: 180, max: 280)
        }
        .onChange(of: selection) { _, sel in
            guard let sel, sel != detailId, let e = rows.first(where: { $0.id == sel }) else { return }
            if e.isFolder {
                selection = nil
                Task { await model.load(e.path) }
            } else {
                show(FileRef(path: e.path, name: e.name))
            }
        }
        // The highlighted row follows the detail column (and is seeded when the table appears).
        .onChange(of: model.previewing, initial: true) { _, _ in selection = detailId }
        .onChange(of: model.editing) { _, _ in selection = detailId }
        .onChange(of: model.consoleOpen) { _, _ in selection = detailId }
        .alert("Discard unsaved changes?", isPresented: discardPresented, presenting: pendingSwitch) { p in
            Button("Discard", role: .destructive) {
                model.closeEditor()
                if p.edit { edit(p.ref) } else { show(p.ref) }
            }
            Button("Keep editing", role: .cancel) { selection = detailId }
        } message: { _ in
            Text("The file open in the editor has edits that were not saved to the PC.")
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let e = rows.first(where: { $0.id == id }) {
                if e.isFolder {
                    Button { Task { await model.load(e.path) } } label: { Label("Open", systemImage: "folder") }
                } else {
                    let ref = FileRef(path: e.path, name: e.name)
                    Button { show(ref) } label: { Label("Preview", systemImage: "eye") }
                    Button { edit(ref) } label: { Label("Open / edit", systemImage: "pencil") }
                    Button { Task { await model.openExternally(ref) } } label: { Label("Open with another app", systemImage: "arrow.up.right.square") }
                    Button { Task { await model.saveToDevice(ref) } } label: { Label("Save to this device", systemImage: "arrow.down.to.line") }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.upload(urls) }
            return true
        }
        .overlay {
            if rows.isEmpty && !model.loading { EmptyBox(message: "Empty folder") }
        }
    }

    private var discardPresented: Binding<Bool> {
        Binding(get: { pendingSwitch != nil }, set: { if !$0 { pendingSwitch = nil } })
    }

    /// Previewing a file replaces whatever the detail column shows (editor, console), so the highlighted row and
    /// the detail column never disagree. Unsaved editor text asks first.
    private func show(_ ref: FileRef) {
        if model.editing == ref { return }                      // already open in the editor: nothing to change
        if model.editing != nil, model.editorDirty { pendingSwitch = PendingSwitch(ref: ref, edit: false); return }
        if model.editing != nil { model.closeEditor() }
        model.consoleOpen = false
        model.previewing = ref
    }

    /// Opening a file in the editor goes through the same guard as previewing.
    private func edit(_ ref: FileRef) {
        if model.editing == ref { return }
        if model.editing != nil, model.editorDirty { pendingSwitch = PendingSwitch(ref: ref, edit: true); return }
        if model.editing != nil { model.closeEditor() }
        model.consoleOpen = false
        model.previewing = nil
        model.editing = ref
    }

    @ViewBuilder
    private func icon(_ e: FolderEntry) -> some View {
        if e.isFolder {
            Image(systemName: FB.folderIcon(e.name))
                .foregroundStyle(FB.folderTint(e.name) ?? FB.blue)
                .frame(width: 24)
        } else {
            let v = FB.fileVisual(e.name)
            Image(systemName: v.icon)
                .foregroundStyle(v.tint ?? Color.secondary)
                .frame(width: 24)
        }
    }
}
