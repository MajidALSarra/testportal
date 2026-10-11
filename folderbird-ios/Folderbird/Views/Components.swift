import SwiftUI
import SafariServices
import WebKit
import PDFKit
import ImageIO
import UIKit

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Brand lockup: the mark + the "Folderbird" wordmark. Not centre-aligned: the wordmark's BASELINE sits on the
/// folder's bottom edge, as in the lockup artwork — that edge is 78.15% down the mark's square canvas.
struct BrandLogo: View {
    var markSize: CGFloat = 40
    var textSize: CGFloat = 22
    var showText = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: textSize * 0.27) {
            Image("FbMark")
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)
                .alignmentGuide(.firstTextBaseline) { d in d.height * 0.7815 }
                .accessibilityLabel("Folderbird")
            if showText {
                // One capital — the brand rule, and what the website shows. Medium weight ≈ the lockup's Poppins Medium.
                Text("Folderbird")
                    .font(.system(size: textSize, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
    }
}

/// Upload/download progress bar, pinned at the bottom of the browser.
struct XferBar: View {
    let x: Xfer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(x.label)
                    .font(.footnote)
                    .lineLimit(1)
                    .foregroundStyle(x.error ? Color.red : Color.primary)
                Spacer()
                if !x.done, let f = x.frac {
                    Text("\(Int(f * 100))%").font(.caption).foregroundStyle(.secondary)
                }
            }
            if x.error {
                EmptyView()                                   // no bar on failure, just the message
            } else if x.done {
                ProgressView(value: 1.0)
            } else if let f = x.frac {
                ProgressView(value: f)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

/// A short bottom message that fades out on its own (the Android Toast).
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let m = message {
                Text(m)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: m) {
                        try? await Task.sleep(nanoseconds: 2_800_000_000)
                        if message == m { message = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}

/// In-app browser for the website's marketing/legal pages (the iOS twin of a Custom Tab).
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController(url: url)
        c.preferredControlTintColor = UIColor(FB.blue)
        return c
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// The system share sheet for a local file.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Renders the server's tokenized /preview page (Office formats). The page gets ONLY the short-lived token URL —
/// never the API key.
struct WebView: UIViewRepresentable {
    let url: URL
    var onError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }

    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        v.navigationDelegate = context.coordinator
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        if context.coordinator.loaded != url {
            context.coordinator.loaded = url
            v.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: URL?
        let onError: ((String) -> Void)?
        init(onError: ((String) -> Void)?) { self.onError = onError }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError?("Preview failed to load: \(error.localizedDescription)")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError?("Preview failed to load: \(error.localizedDescription)")
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame, let r = navigationResponse.response as? HTTPURLResponse, r.statusCode >= 400 {
                onError?("Preview failed to load (HTTP \(r.statusCode))")
            }
            decisionHandler(.allow)
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayDirection = .vertical
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document }
    }
}

/// Decode an image sampled down so a very large photo can't exhaust memory. A 40-megapixel picture decodes to
/// roughly 160 MB — ImageIO's thumbnail path reads the header and decodes at a bounded size instead.
func decodeBounded(_ url: URL, maxPixels: Int = 2560) -> UIImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    return UIImage(cgImage: cg)
}

func appVersion() -> String {
    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    return b.isEmpty ? v : "\(v) (\(b))"
}

/// Reads a text file as UTF-8, falling back to Latin-1 so a legacy Windows file still shows something.
func readText(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    if let s = String(data: data, encoding: .utf8) { return s }
    return String(data: data, encoding: .isoLatin1)
}
