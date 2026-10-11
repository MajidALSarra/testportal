import SwiftUI

/// Navigate the device (This PC → drives → folders) and pick a destination folder for the upload.
@MainActor
struct FolderPickerView: View {
    let deviceId: String
    let start: String?
    let onCancel: () -> Void
    let onPick: (String) -> Void

    @State private var path: String?
    @State private var listing: FilesResponse?
    @State private var drives: [Disk]?
    @State private var loading = true
    @State private var error: String?

    private var api: Api { Api(Prefs.shared) }

    var body: some View {
        VStack(spacing: 0) {
            CrumbBar(path: path) { target in Task { await load(target) } }
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(path == nil ? "Pick a drive, then a folder" : "Upload to:  \(path ?? "")")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                Button { if let p = path { onPick(p) } } label: {
                    Text("Upload here").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(path == nil)
            }
            .padding(16)
        }
        .navigationTitle("Choose a folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Back") { onCancel() } }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { if path == nil { await loadDrives() } else { await load(path) } } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await landing() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            CenterProgress()
        } else if let e = error {
            ErrorBox(message: e) { Task { if path == nil { await loadDrives() } else { await load(path) } } }
        } else if path == nil {
            List {
                Section("This PC") {
                    ForEach(drives ?? []) { d in
                        Button { Task { await load(d.root) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "internaldrive").foregroundStyle(FB.blue)
                                Text(d.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if (drives ?? []).isEmpty {
                        Text("No drives reported — the device may be offline.").foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        } else {
            let folders = sortFolders(listing?.folders ?? [])
            List {
                if folders.isEmpty {
                    Text("No sub-folders here. Use “Upload here” to drop the file in this folder.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(folders, id: \.self) { f in
                    let nm = f.name ?? f.path ?? ""
                    Button { if let p = f.path { Task { await load(p) } } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: FB.folderIcon(nm)).foregroundStyle(FB.folderTint(nm) ?? FB.blue).frame(width: 28)
                            Text(nm).fontWeight(.medium).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func landing() async {
        var landingPath = start
        if landingPath == nil { landingPath = await api.resolveHomeFolder(deviceId) }
        await load(landingPath)
    }

    private func loadDrives() async {
        path = nil; error = nil; loading = true; listing = nil
        do {
            let sys = try await api.system(deviceId)
            drives = sys.disks.filter { !($0.drive ?? "").isEmpty }
        } catch let e {
            error = errorMessage(e)
        }
        loading = false
    }

    private func load(_ p: String?) async {
        path = p; error = nil; loading = true
        do {
            if let p {
                listing = try await api.files(deviceId, path: p)
            } else {
                listing = nil
                if drives == nil {
                    let sys = try await api.system(deviceId)
                    drives = sys.disks.filter { !($0.drive ?? "").isEmpty }
                }
            }
        } catch let e {
            error = errorMessage(e)
            if p != nil { listing = nil }
        }
        loading = false
    }
}
