import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import UIKit

enum BrowseLayout { case compact, regular }

/// The file browser for one device: breadcrumbs, "This PC" drives, folders & files, search, upload, new folder,
/// and (on the phone) the docked preview panel. On the iPad the preview, editor and console live in the detail
/// column instead — see DetailPane.
@MainActor
struct BrowseView: View {
    @ObservedObject var model: BrowseModel
    let layout: BrowseLayout

    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var workspace: Workspace
    @State private var newFolderOpen = false
    @State private var newFolderName = ""
    @State private var showImporter = false
    @State private var previewFrac: CGFloat = 0.5
    @State private var shareItem: IdentifiableURL?

    var body: some View {
        VStack(spacing: 0) {
            CrumbBar(path: model.path) { target in Task { await model.load(target) } }
            Divider()
            if model.searchOpen {
                Toggle("Search inside file contents", isOn: $model.inContent)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                Divider()
            }
            GeometryReader { geo in
                VStack(spacing: 0) {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The file list takes the space above the docked preview panel, so it stays scrollable and
                    // tappable while a preview is open below it. Drag the handle to resize.
                    if layout == .compact, let f = model.previewing {
                        PreviewPanel(model: model, file: f, docked: true) { delta in
                            previewFrac = min(0.92, max(0.35, previewFrac - delta / max(geo.size.height, 1)))
                        }
                        .id(f.path)
                        .frame(height: geo.size.height * previewFrac)
                    }
                }
            }
            if let x = model.xfer { XferBar(x: x) }
        }
        .navigationTitle(model.device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .searchable(text: $model.query, isPresented: $model.searchOpen,
                    prompt: model.path == nil ? "Search this device" : "Search in current folder")
        .onSubmit(of: .search) { Task { await model.runSearch() } }
        .onChange(of: model.searchOpen) { _, open in if !open { model.closeSearch() } }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.upload(urls) } }
        }
        .alert("New folder", isPresented: $newFolderOpen) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let n = newFolderName.trimmingCharacters(in: .whitespaces)
                newFolderName = ""
                if !n.isEmpty { Task { await model.createFolder(named: n) } }
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Discard unsaved changes?", isPresented: $model.pendingConsoleDiscard) {
            Button("Discard", role: .destructive) { model.discardAndOpenConsole() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("The file open in the editor has edits that were not saved to the PC.")
        }
        .alert("Saved to this \(UIDevice.current.model)", isPresented: savedPresented, presenting: model.saved) { s in
            // Share is a CHOICE, not something that pops open on its own.
            Button("Share") { shareItem = IdentifiableURL(url: s.url) }
            Button("Done", role: .cancel) {}
        } message: { s in
            Text("\(s.name)\n\nIn \(s.location) — you can find it any time in the Files app.")
        }
        .sheet(item: $shareItem) { ActivityView(url: $0.url) }
        .quickLookPreview($model.quickLookURL)
        .modifier(CompactRoutes(model: model, enabled: layout == .compact))
        .toast($model.toast)
        .onAppear { if layout == .compact { workspace.selectedDeviceId = model.deviceId } }
        .task { await model.landIfNeeded() }
    }

    private var savedPresented: Binding<Bool> {
        Binding(get: { model.saved != nil }, set: { if !$0 { model.saved = nil } })
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.path != nil {
                Menu {
                    Button { showImporter = true } label: { Label("Upload file here", systemImage: "square.and.arrow.up") }
                        .keyboardShortcut("u", modifiers: .command)
                    Button { newFolderOpen = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                } label: {
                    Image(systemName: "plus")
                }
                .help("Upload or create a folder")
                Button { Task { await model.goUp() } } label: { Image(systemName: "arrow.up") }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("Up one folder")
            }
            Button { model.openConsole() } label: { Image(systemName: "terminal") }
                .keyboardShortcut("t", modifiers: .command)
                .help("Command console")
            Button {
                if model.searchOpen { model.closeSearch() } else { model.searchOpen = true }
            } label: { Image(systemName: "magnifyingglass") }
                .keyboardShortcut("f", modifiers: .command)
                .help("Search")
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.searching {
            CenterProgress()
        } else if let e = model.error {
            ErrorBox(message: e) { Task { await model.retry() } }
        } else if let r = model.results {
            SearchResultsList(results: r,
                              onOpenFolder: { folder in model.closeSearch(); Task { await model.load(folder) } },
                              onDownload: { r in Task { await model.saveToDevice(FileRef(path: r.path ?? "", name: r.name)) } })
        } else if model.loading && (model.path == nil || layout == .compact) {
            CenterProgress()
        } else if model.path == nil {
            DrivesList(model: model)
        } else if layout == .regular {
            // The table stays mounted while a folder loads, so its sort order and selection survive a reload.
            FolderTable(model: model)
                .overlay {
                    if model.loading {
                        ZStack {
                            Color(uiColor: .systemBackground).opacity(0.6)
                            ProgressView()
                        }
                    }
                }
        } else {
            FolderList(model: model)
        }
    }
}

/// Phone-only: the console and the editor push onto the navigation stack (on iPad they are the detail column).
@MainActor
private struct CompactRoutes: ViewModifier {
    @ObservedObject var model: BrowseModel
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .navigationDestination(isPresented: $model.consoleOpen) { ConsoleView(model: model).toast($model.toast) }
                .navigationDestination(item: $model.editing) { f in FileViewerView(model: model, file: f).toast($model.toast) }
        } else {
            content
        }
    }
}

// MARK: - This PC

@MainActor
struct DrivesList: View {
    @ObservedObject var model: BrowseModel

    var body: some View {
        if model.drivesLoading {
            CenterProgress()
        } else if let e = model.drivesError {
            let offline = e.localizedCaseInsensitiveContains("offline") || e.contains("504") || e.localizedCaseInsensitiveContains("did not respond")
            ErrorBox(message: offline ? "This device is offline.\nStart the Folderbird app on it, then tap Retry."
                                      : "Couldn't read the drives.\n\(e)") { Task { await model.loadDrives() } }
        } else if (model.drives ?? []).isEmpty {
            EmptyBox(message: "No drives reported.\nThe device may be offline — tap refresh to try again.")
        } else {
            List {
                Section("This PC") {
                    ForEach(model.drives ?? []) { d in
                        Button { Task { await model.load(d.root) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "internaldrive").foregroundStyle(FB.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.title).foregroundStyle(.primary)
                                    if d.totalGB != nil {
                                        Text("\(fmtGb(d.freeGB)) free of \(fmtGb(d.totalGB))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refresh() }
        }
    }
}

// MARK: - Folder listing

@MainActor
struct FolderList: View {
    @ObservedObject var model: BrowseModel

    var body: some View {
        let listing = model.listing ?? FilesResponse()
        let folders = sortFolders(listing.folders)
        List {
            ForEach(folders, id: \.self) { f in
                let fname = f.name ?? f.path ?? ""
                Button { if let p = f.path { Task { await model.load(p) } } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: FB.folderIcon(fname))
                            .font(.title3)
                            .foregroundStyle(FB.folderTint(fname) ?? FB.blue)
                            .frame(width: 28)
                        Text(fname).fontWeight(.medium).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            ForEach(listing.files, id: \.self) { file in
                let nm = (file.name ?? "").isEmpty ? "download" : (file.name ?? "")
                let ref = FileRef(path: PathUtil.join(model.path ?? "", nm), name: nm)
                FileRow(model: model, file: file, ref: ref)
            }
            if folders.isEmpty && listing.files.isEmpty {
                Text("Empty folder").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(28)
            }
        }
        .listStyle(.plain)
        .refreshable { await model.refresh() }
        // iPad: drop files from the Files app (or another window) straight into this folder.
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.upload(urls) }
            return true
        }
    }
}

@MainActor
struct FileRow: View {
    @ObservedObject var model: BrowseModel
    let file: FileItem
    let ref: FileRef

    private var selected: Bool { model.previewing == ref }

    var body: some View {
        let v = FB.fileVisual(ref.name)
        HStack(spacing: 12) {
            Image(systemName: v.icon)
                .font(.title3)
                .foregroundStyle(v.tint ?? Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.name).lineLimit(1)
                let meta = fileMeta(file)
                if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Actions")
        }
        .contentShape(Rectangle())
        .onTapGesture { model.previewing = ref }
        .contextMenu { actions }
        .swipeActions(edge: .trailing) {
            Button { Task { await model.saveToDevice(ref) } } label: { Label("Save", systemImage: "arrow.down.to.line") }
                .tint(FB.success)
        }
        .listRowBackground(selected ? FB.blue.opacity(0.12) : nil)
    }

    @ViewBuilder
    private var actions: some View {
        Button { model.previewing = ref } label: { Label("Preview", systemImage: "eye") }
        Button { model.previewing = nil; model.editing = ref } label: { Label("Open / edit", systemImage: "pencil") }
        Button { Task { await model.openExternally(ref) } } label: { Label("Open with another app", systemImage: "arrow.up.right.square") }
        Button { Task { await model.saveToDevice(ref) } } label: { Label("Save to this device", systemImage: "arrow.down.to.line") }
    }
}

// MARK: - Search results

struct SearchResultsList: View {
    let results: [SearchResult]
    let onOpenFolder: (String) -> Void
    let onDownload: (SearchResult) -> Void

    var body: some View {
        if results.isEmpty {
            EmptyBox(message: "No matches.")
        } else {
            List {
                Section(header: Text("\(results.count) result(s)")) {
                    ForEach(results) { r in
                        let v = FB.fileVisual(r.name)
                        HStack(spacing: 12) {
                            Image(systemName: v.icon).foregroundStyle(v.tint ?? Color.secondary).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).lineLimit(1)
                                Text(r.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button { onDownload(r) } label: { Image(systemName: "arrow.down.to.line") }
                                .buttonStyle(.borderless)
                                .help("Save to this device")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if !r.folder.isEmpty { onOpenFolder(r.folder) } }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
