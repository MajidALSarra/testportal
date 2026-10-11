import SwiftUI

/// The share flow: what was shared → pick an online device → pick (or reuse) a target folder → Send, then a
/// terminal success / partly / failed screen whose OK returns the user to the app they shared from.
@MainActor
struct ShareRootView: View {
    let onDone: () -> Void
    @StateObject private var prefs = Prefs.shared
    @StateObject private var vm: ShareModel

    init(payload: SharedPayload, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _vm = StateObject(wrappedValue: ShareModel(payload: payload))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.picking, let d = vm.selected {
                    FolderPickerView(deviceId: d.idStr, start: vm.folder,
                                     onCancel: { vm.picking = false },
                                     onPick: { vm.folder = $0; vm.picking = false })
                } else if let res = vm.result, !vm.uploading {
                    resultScreen(res)
                } else {
                    form
                }
            }
        }
        .tint(FB.blue)
        .preferredColorScheme(prefs.themeMode == "light" ? .light : (prefs.themeMode == "dark" ? .dark : nil))
        .task { await vm.prepare() }
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summary
                Spacer().frame(height: 20)
                if let e = vm.prepError {
                    Text(e).foregroundStyle(.red)
                } else if vm.loadingDevices {
                    HStack(spacing: 12) { ProgressView(); Text("Loading devices…") }
                } else if let e = vm.loadError {
                    Text("Couldn't load devices: \(e)").foregroundStyle(.red)
                    Button("Retry") { Task { await vm.loadDevices() } }.buttonStyle(.borderedProminent).padding(.top, 12)
                } else if vm.online.isEmpty {
                    Text("No devices are online.").font(.headline)
                    Text("Open the Folderbird app on the PC you want to send to, then tap Retry.")
                        .font(.callout).foregroundStyle(.secondary).padding(.top, 4)
                    Button("Retry") { Task { await vm.loadDevices() } }.buttonStyle(.borderedProminent).padding(.top, 14)
                } else {
                    targetPicker
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Send to a device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() }.disabled(vm.uploading) }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if vm.fileNames.isEmpty {
            Text("Preparing…").font(.callout).foregroundStyle(.secondary)
        } else if vm.fileNames.count == 1 {
            Text(vm.fileNames[0]).font(.callout).foregroundStyle(.secondary)
        } else {
            // Multi-select: say how many, then list the first few so the user can confirm it's the right batch.
            Text("\(vm.fileNames.count) files").font(.callout).fontWeight(.medium)
            let shown = vm.fileNames.prefix(4)
            Text(shown.joined(separator: "\n") + (vm.fileNames.count > shown.count ? "\n… and \(vm.fileNames.count - shown.count) more" : ""))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var devicePicker: Binding<String> {
        Binding(get: { vm.selectedId },
                set: { id in if let d = vm.devices.first(where: { $0.idStr == id }) { Task { await vm.select(d) } } })
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Device").font(.subheadline.weight(.semibold))
            Picker("Device", selection: devicePicker) {
                ForEach(vm.online) { d in
                    Text(d.displayName + (d.isSlow ? "  · " + d.statusLabel.replacingOccurrences(of: "online · ", with: "") : "")).tag(d.idStr)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            Spacer().frame(height: 10)
            Text("Target folder on the device").font(.subheadline.weight(.semibold))
            if let f = vm.folder, !f.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(FB.blue)
                    Text(f).font(.callout).lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            Button { vm.picking = true } label: {
                Label((vm.folder ?? "").isEmpty ? "Choose folder" : "Choose a different folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(vm.selected == nil)

            // Recent folders: one tap to reuse a destination, no navigating.
            let recents = prefs.recentFolders().filter { $0 != vm.folder }
            if vm.selected != nil, !recents.isEmpty {
                Text("Recent folders").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recents, id: \.self) { rf in
                            Button { vm.folder = rf } label: {
                                Label(PathUtil.shortFolderLabel(rf), systemImage: "folder").lineLimit(1).font(.footnote)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    }
                }
            }

            Spacer().frame(height: 16)
            Button { Task { await vm.send() } } label: {
                Text(vm.uploading ? "Sending…" : (vm.total > 1 ? "Send \(vm.total) files" : "Send"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canSend)

            if vm.uploading {
                // Three honest phases: preparing (indeterminate), uploading (real %), and — once all bytes have
                // left the device — "sending to the PC" (indeterminate again; the server is still delivering).
                let f = vm.uploadFrac
                if f == nil || f == 0 || (f ?? 0) >= 1 { ProgressView().progressViewStyle(.linear) }
                else { ProgressView(value: f ?? 0) }
                let phase: String = {
                    guard let f, f > 0 else { return "Preparing…" }
                    return f >= 1 ? "Sending to the PC…" : "Uploading… \(Int(f * 100))%"
                }()
                Text(vm.total > 1 ? "File \(vm.currentIndex + 1) of \(vm.total) · \(vm.currentName.isEmpty ? "…" : vm.currentName)\n\(phase)" : phase)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Result

    private func resultScreen(_ res: String) -> some View {
        let ok = !res.hasPrefix("Failed") && !res.hasPrefix("Partly")
        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(ok ? FB.success : Color.red)
            Text(ok ? "Uploaded" : (res.hasPrefix("Partly") ? "Partly uploaded" : "Upload failed")).font(.title2.weight(.semibold))
            Text(res).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Button { onDone() } label: { Text("OK").frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .navigationTitle("Send to a device")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
final class ShareModel: ObservableObject {
    let payload: SharedPayload

    @Published var fileNames: [String] = []
    @Published var prepError: String?
    @Published var devices: [Device] = []
    @Published var selectedId = ""
    @Published var folder: String?
    @Published var loadingDevices = true
    @Published var loadError: String?
    @Published var picking = false
    @Published var uploading = false
    @Published var uploadFrac: Double?
    @Published var currentIndex = 0
    @Published var currentName = ""
    @Published var sentCount = 0
    @Published var result: String?

    private var prefs: Prefs { Prefs.shared }
    private var api: Api { Api(prefs) }

    init(payload: SharedPayload) { self.payload = payload }

    var online: [Device] { devices.filter { $0.isOnline } }
    var selected: Device? { devices.first { $0.idStr == selectedId } }
    var total: Int { payload.items.count }
    var canSend: Bool {
        !uploading && total > 0 && prepError == nil && (selected?.isOnline ?? false) && !(folder ?? "").isEmpty
    }

    func prepare() async {
        prefs.reload()
        guard prefs.isConfigured else {
            prepError = "Open the Folderbird app and sign in first."
            loadingDevices = false
            return
        }
        guard !payload.items.isEmpty else {
            prepError = "Nothing was shared."
            loadingDevices = false
            return
        }
        fileNames = payload.items.enumerated().map { i, item in item.displayName(index: i) }
        await loadDevices()
    }

    func loadDevices() async {
        loadingDevices = true; loadError = nil
        do {
            devices = try await api.devices()
            loadingDevices = false
            // The home-folder lookup is one or two more device round trips — don't hold the list for it;
            // select() only fills `folder` if the user hasn't picked one meanwhile.
            if selected == nil, let first = online.first { Task { await self.select(first) } }
        } catch let e {
            loadError = errorMessage(e)
            loadingDevices = false
        }
    }

    /// When a device is chosen, default the target to its home folder (like the website), overridable via the picker.
    func select(_ d: Device) async {
        guard d.idStr != selectedId else { return }
        selectedId = d.idStr
        folder = nil
        guard d.isOnline else { return }
        let home = await api.resolveHomeFolder(d.idStr)
        if selectedId == d.idStr && folder == nil {
            folder = home ?? (prefs.lastUploadFolder.isEmpty ? nil : prefs.lastUploadFolder)
        }
    }

    /// Items go up ONE AT A TIME, in the order they were selected: each upload is a full round trip to the PC,
    /// and firing them in parallel would just contend for the same device channel.
    func send() async {
        guard let d = selected, let target = folder, !target.isEmpty, !uploading else { return }
        uploading = true; result = nil; uploadFrac = 0; sentCount = 0; currentIndex = 0
        prefs.lastUploadFolder = target
        var failures: [String] = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fb-share-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for (i, item) in payload.items.enumerated() {
            currentIndex = i; uploadFrac = 0
            currentName = fileNames.indices.contains(i) ? fileNames[i] : ""
            do {
                let (file, name) = try await ShareStaging.stage(item, into: dir)
                currentName = name
                defer { try? FileManager.default.removeItem(at: file) }   // free the cache as we go
                try await Transfers.upload(api: api, deviceId: d.idStr, folder: target, fileURL: file, fileName: name) { [weak self] f in
                    self?.uploadFrac = f
                }
                sentCount += 1
            } catch let e {
                failures.append("\(currentName.isEmpty ? "file \(i + 1)" : currentName): \(errorMessage(e))")
            }
        }
        uploading = false; uploadFrac = nil
        if sentCount > 0 { prefs.addRecentFolder(target) }

        let n = payload.items.count
        if failures.isEmpty && n == 1 {
            result = "Sent \"\(currentName)\" to \(d.displayName) → \(target)"
        } else if failures.isEmpty {
            result = "Sent \(sentCount) files to \(d.displayName) → \(target)"
        } else if sentCount == 0 && n == 1 {
            let f = failures[0]
            let reason = f.range(of: ": ").map { String(f[$0.upperBound...]) } ?? f
            result = "Failed: \(reason)"
        } else if sentCount == 0 {
            result = "Failed: none of the \(n) files could be sent.\n" + failures.prefix(3).joined(separator: "\n")
        } else {
            result = "Partly: \(sentCount) of \(n) files reached \(d.displayName) → \(target).\nNot sent:\n"
                + failures.prefix(5).joined(separator: "\n")
                + (failures.count > 5 ? "\n… and \(failures.count - 5) more" : "")
        }
    }
}
