import SwiftUI

struct MoreLink: Identifiable {
    let id: String
    let icon: String
    let label: String
    /// Website path (relative to the server URL); nil opens Account & settings.
    let path: String?
}

/// Website-consistent links: the marketing/legal pages are opened live from the site so they are always current.
enum MoreLinks {
    static let account: [MoreLink] = [
        MoreLink(id: "settings", icon: "gearshape", label: "Account & settings", path: nil),
        MoreLink(id: "manage", icon: "person.crop.circle", label: "Manage account on website", path: "/Manage"),
    ]
    static let folderbird: [MoreLink] = [
        MoreLink(id: "web", icon: "globe", label: "Open website", path: ""),
        MoreLink(id: "about", icon: "info.circle", label: "About", path: "/about"),
        MoreLink(id: "pricing", icon: "creditcard", label: "Pricing & plans", path: "/Pricing"),
        MoreLink(id: "contact", icon: "envelope", label: "Contact / support", path: "/contact"),
    ]
    static let legal: [MoreLink] = [
        MoreLink(id: "privacy", icon: "hand.raised", label: "Privacy Policy", path: "/privacy"),
        MoreLink(id: "terms", icon: "doc.text", label: "Terms of Service", path: "/terms"),
        MoreLink(id: "refund", icon: "arrow.uturn.backward.circle", label: "Refund Policy", path: "/refund"),
    ]
}

/// Rows for a List: tapping opens the page in-app, or Account & settings for the nil path.
struct MoreLinkRows: View {
    let links: [MoreLink]
    let onSettings: () -> Void
    let onOpen: (URL) -> Void
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        ForEach(links) { l in
            Button {
                if let p = l.path {
                    if let u = URL(string: prefs.normalizedBase + p) { onOpen(u) }
                } else {
                    onSettings()
                }
            } label: {
                Label(l.label, systemImage: l.icon).foregroundStyle(.primary)
            }
        }
    }
}

struct MoreView: View {
    @EnvironmentObject var prefs: Prefs
    @State private var safari: IdentifiableURL?

    var body: some View {
        List {
            Section {
                BrandLogo(markSize: 40, textSize: 26)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
            }
            Section("Account") {
                NavigationLink { SettingsView() } label: {
                    Label("Account & settings", systemImage: "gearshape")
                }
                MoreLinkRows(links: Array(MoreLinks.account.dropFirst()), onSettings: {}, onOpen: open)
            }
            Section("Folderbird") {
                MoreLinkRows(links: MoreLinks.folderbird, onSettings: {}, onOpen: open)
            }
            Section("Legal") {
                MoreLinkRows(links: MoreLinks.legal, onSettings: {}, onOpen: open)
            }
            Section {
                Text("Folderbird • Riyadh, Saudi Arabia\nv\(appVersion())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("More")
        .sheet(item: $safari) { SafariView(url: $0.url) }
    }

    private func open(_ url: URL) { safari = IdentifiableURL(url: url) }
}
