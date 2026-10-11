import SwiftUI

// Small building blocks used by both the app and the share extension (nothing here touches UIApplication).

struct CenterProgress: View {
    var body: some View { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
}

struct ErrorBox: View {
    let message: String
    var retryTitle = "Retry"
    let onRetry: () -> Void
    var secondary: (title: String, action: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text(message).font(.callout).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(retryTitle, action: onRetry).buttonStyle(.borderedProminent)
                if let s = secondary { Button(s.title, action: s.action).buttonStyle(.bordered) }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyBox: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Breadcrumbs: This PC › C: › Users › …  (or This PC › / › root › … for a Linux device).
struct CrumbBar: View {
    let path: String?
    let onNavigate: (String?) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    Crumb(text: "This PC", active: path == nil) { onNavigate(nil) }
                    if let p = path {
                        let crumbs = PathUtil.crumbs(p)
                        ForEach(crumbs) { c in
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            Crumb(text: c.label, active: c.id == crumbs.count - 1) { onNavigate(c.target) }
                                .id(c.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: path) { _, newPath in
                let n = PathUtil.crumbs(newPath ?? "").count
                if n > 0 { withAnimation { proxy.scrollTo(n - 1, anchor: .trailing) } }
            }
        }
    }
}

struct Crumb: View {
    let text: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button { if !active { action() } } label: {
            Text(text)
                .font(.callout.weight(active ? .bold : .regular))
                .foregroundStyle(active ? Color.primary : FB.blue)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
