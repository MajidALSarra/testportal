import SwiftUI
import PDFKit
import UIKit

/// Quick preview of one file: text, images and PDFs are rendered on the device from the downloaded bytes; Office
/// formats load the server's tokenized /preview page in a web view. Docked (bottom half, resizable) on the phone;
/// the full detail column on iPad.
@MainActor
struct PreviewPanel: View {
    @ObservedObject var model: BrowseModel
    let file: FileRef
    let docked: Bool
    var onResize: ((CGFloat) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @State private var loading = true
    @State private var progress: Double?
    @State private var error: String?
    @State private var text: String?
    @State private var image: UIImage?
    @State private var pdf: PDFDocument?
    @State private var previewURL: URL?
    @State private var lastDrag: CGFloat = 0

    private var name: String { file.name }
    private var isText: Bool { FB.isText(name) }
    private var isImage: Bool { FB.isImage(name) }
    private var isPdf: Bool { FB.isPdf(name) }
    private var isOffice: Bool { FB.isOffice(name) }
    private var renderable: Bool { isText || isImage || isPdf || isOffice }

    var body: some View {
        VStack(spacing: 8) {
            if docked { handle }
            header
            if loading {
                if let p = progress { ProgressView(value: p) } else { ProgressView().progressViewStyle(.linear) }
                Text("Loading preview…").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 6)
            Divider()
            actionsRow
        }
        .padding(.horizontal, 16)
        .background(Color(uiColor: docked ? .secondarySystemBackground : .systemBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: docked ? 16 : 0, topTrailingRadius: docked ? 16 : 0))
        .shadow(color: Color.black.opacity(docked ? 0.15 : 0), radius: 8, y: -2)
        .task(id: file.path) { await load() }
    }

    private var handle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        let delta = v.translation.height - lastDrag
                        lastDrag = v.translation.height
                        onResize?(delta)
                    }
                    .onEnded { _ in lastDrag = 0 }
            )
    }

    private var header: some View {
        HStack(spacing: 10) {
            let v = FB.fileVisual(name)
            Image(systemName: v.icon).foregroundStyle(v.tint ?? FB.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if isPdf, let p = pdf, p.pageCount > 0 {
                    Text("\(p.pageCount) page\(p.pageCount == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { model.previewing = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close preview")
        }
        .padding(.top, docked ? 0 : 12)
    }

    @ViewBuilder
    private var contentArea: some View {
        if let e = error {
            Text(e).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isText, let t = text {
            ScrollView {
                Text(t)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if isImage, let img = image {
            // Fit, not fill: the largest size that fits the panel in BOTH axes, keeping the proportions.
            Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isPdf, let doc = pdf {
            PDFKitView(document: doc)
        } else if isOffice, let u = previewURL {
            WebView(url: u) { msg in error = msg }
        } else if !renderable && !loading {
            Text("No inline preview for .\(FB.ext(name)) files — use the actions below.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            if isText {
                Button { model.previewing = nil; model.consoleOpen = false; model.editing = file } label: {
                    Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button { Task { await model.openExternally(file) } } label: {
                Label("Open", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button { Task { await model.saveToDevice(file) } } label: {
                Label("Save", systemImage: "arrow.down.to.line").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 10)
    }

    /// The preview page renders inside OUR panel, so it must follow the APP's theme, not the device setting —
    /// otherwise a white page appears inside a dark app.
    private func themed(_ s: String) -> URL? {
        let sep = s.contains("?") ? "&" : "?"
        return URL(string: s + sep + "theme=" + (scheme == .dark ? "dark" : "light"))
    }

    private func load() async {
        loading = renderable; progress = nil; error = nil
        text = nil; image = nil; pdf = nil; previewURL = nil
        guard renderable else { return }
        let api = Api(Prefs.shared)
        if isOffice {
            // Rendered by the server's tokenized preview page — don't pull the bytes here.
            do {
                let link = try await api.previewLink(model.deviceId, path: file.path)
                if let u = link.preview_url, !u.isEmpty, let url = themed(u) { previewURL = url }
                else { error = "Couldn't prepare this preview — use the actions below." }
            } catch let e {
                if !isCancellation(e) { error = errorMessage(e) }
            }
            loading = false
            return
        }
        do {
            // Streams to a cache file, so Open, Save and the full viewer reuse the bytes instead of fetching again.
            let local = try await PreviewCache.shared.fetch(api: api, deviceId: model.deviceId, fullPath: file.path,
                                                            fileName: name) { f in progress = f }
            if isText {
                let t = await Task.detached(priority: .userInitiated) { readText(local) }.value
                text = t
                if t == nil { error = "Couldn't render this file — use the actions below." }
            } else if isImage {
                let decoded = await Task.detached(priority: .userInitiated) { decodeBounded(local) }.value
                image = decoded
                if decoded == nil { error = "Couldn't render this file — use the actions below." }
            } else if isPdf {
                pdf = PDFDocument(url: local)
                if pdf == nil { error = "Couldn't render this file — use the actions below." }
            }
        } catch let e {
            if !isCancellation(e) { error = errorMessage(e) }
        }
        loading = false
    }
}
