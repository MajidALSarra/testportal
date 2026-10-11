import SwiftUI

@main
struct FolderbirdApp: App {
    @StateObject private var prefs = Prefs.shared
    @StateObject private var auth = AuthState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(prefs)
                .environmentObject(auth)
                .tint(FB.blue)
                // Theme preference: "system" follows the device; "light" / "dark" force it (as on Android).
                .preferredColorScheme(prefs.themeMode == "light" ? .light : (prefs.themeMode == "dark" ? .dark : nil))
                .onOpenURL { url in handle(url) }
        }
        // iPad: ⌘-key menu entries for the sidebar; per-screen shortcuts are declared on their buttons.
        .commands { SidebarCommands() }
    }

    /// The folderbird://auth redirect normally comes back through ASWebAuthenticationSession. If the system hands
    /// the app the URL directly (a sign-in finished in Safari), finish the exchange here.
    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "folderbird", url.host?.lowercased() == "auth" else { return }
        Task { @MainActor in
            do {
                let key = try await AuthManager.handleCallback(prefs: prefs, url: url)
                prefs.apiKey = key
            } catch {
                // A cancelled consent page or a stale code: nothing to do, the sign-in screen stays up.
            }
        }
    }
}
