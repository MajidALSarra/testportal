import SwiftUI
import PDFKit
import UIKit

/// Full-size viewer and text editor: text files are edited in place and saved back to the PC; images, PDFs and
/// Office documents are shown read-only; everything else offers Open / Save. The text buffer lives in the
/// device model's EditorDraft, so a device switch or a layout change never loses an unsaved edit.
@MainActor
struct FileViewerView: View {
    @ObservedObject var model: BrowseModel
    @ObservedObject var draft: EditorDraft
    let file: FileRef
    var inDetailColumn = false

    @Environment(\.colorScheme) private var scheme
    @State private var loading = true
    @State private var error: String?
    @State private var reloadKey = 0
    @State private var saving = false
    @State private var saveMsg: String?
    @State private var closePrompt = false
    @State private var image: UIImage?
    @State private var pdf: PDFDocument?
    @State private var previewURL: URL?

    init(model: BrowseModel, file: FileRef, inDetailColumn: Bool = false) {
        self.model = model
        self.file = file
        self.inDetailColumn = inDetailColumn
        _draft = ObservedObject(wrappedValue: model.draft)
    }

    private var name: String { file.name }
    private var isText: Bool { FB.isText(name) }
    private var isImage: Bool { FB.isImage(name) }
    private var isPdf: Bool { FB.isPdf(name) }
    private var isOffice: Bool { FB.isOffice(name) }
    private var dirty: Bool { draft.path == file.path && draft.dirty }

    var body: some View {
        VStack(spacing: 0) {
            if let m = saveMsg {
                Text(m).font(.footnote).foregroundStyle(FB.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 4)
            }
            content
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inDetailColumn {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { if dirty { closePrompt = true } else { model.closeEditor() } }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isText {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!dirty || error != nil || loading)
                            .keyboardShortcut("s", modifiers: .command)
                    }
                }
                Button { Task { await model.openExternally(file) } } label: { Image(systemName: "arrow.up.right.square") }
                    .help("Open with another app")
                Button { Task { await model.saveToDevice(file) } } label: { Image(systemName: "arrow.down.to.line") }
                    .help("Save to this device")
            }
        }
        .alert("Discard unsaved changes?", isPresented: $closePrompt) {
            Button("Discard", role: .destructive) { model.closeEditor() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("The edits were not saved to the PC.")
        }
        .task(id: reloadKey) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            CenterProgress()
        } else if let e = error {
            ErrorBox(message: e) { reloadKey += 1 }
        } else if isText {
            TextEditor(text: $draft.text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
        } else if isImage, let img = image {
            Image(uiImage: img).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(4)
        } else if isPdf, let doc = pdf {
            PDFKitView(document: doc)
        } else if isOffice, let u = previewURL {
            WebView(url: u) { msg in error = msg }
        } else {
            VStack(spacing: 12) {
                Text("No in-app preview for .\(FB.ext(name)) files.").font(.callout)
                Button("Open with another app") { Task { await model.openExternally(file) } }.buttonStyle(.borderedProminent)
                Button("Save to this device") { Task { await model.saveToDevice(file) } }.buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func themed(_ s: String) -> URL? {
        let sep = s.contains("?") ? "&" : "?"
        return URL(string: s + sep + "theme=" + (scheme == .dark ? "dark" : "light"))
    }

    private func load() async {
        // The model already holds this file's buffer (back from another device, a layout change, Quick Look):
        // keep it — including unsaved edits — instead of fetching over it.
        if isText, draft.path == file.path, reloadKey == 0 {
            loading = false
            return
        }
        loading = true; error = nil
        let api = Api(Prefs.shared)
        if isOffice {
            do {
                let link = try await api.previewLink(model.deviceId, path: file.path)
                if let u = link.preview_url, !u.isEmpty, let url = themed(u) { previewURL = url }
                else { error = "Couldn't prepare this preview." }
            } catch let e {
                error = errorMessage(e)
            }
            loading = false
            return
        }
        do {
            // Reuses the preview's copy when there is one — expanding a preview into the full viewer must not
            // pull the whole file down a second time.
            let local = try await PreviewCache.shared.fetch(api: api, deviceId: model.deviceId, fullPath: file.path, fileName: name)
            if isText {
                if let t = await Task.detached(priority: .userInitiated) { readText(local) }.value {
                    draft.path = file.path
                    draft.text = t
                    draft.loadedText = t
                } else {
                    error = "Couldn't read this file as text."
                }
            } else if isImage {
                let decoded = await Task.detached(priority: .userInitiated) { decodeBounded(local) }.value
                image = decoded
                if decoded == nil { error = "Couldn't display this image." }
            } else if isPdf {
                pdf = PDFDocument(url: local)
                if pdf == nil { error = "Couldn't display this PDF." }
            }
        } catch let e {
            error = errorMessage(e)
        }
        loading = false
    }

    private func save() {
        saving = true; saveMsg = nil
        let content = draft.text
        Task {
            do {
                try await Api(Prefs.shared).writeText(model.deviceId, path: file.path, content: content)
                // We just changed the file on the PC — the cached copy is now the OLD text, and Save-to-device
                // must not hand back what was replaced.
                PreviewCache.shared.clear()
                draft.loadedText = content
                saveMsg = "Saved ✓"
            } catch let e {
                saveMsg = "Save failed: \(errorMessage(e))"
            }
            saving = false
        }
    }
}
