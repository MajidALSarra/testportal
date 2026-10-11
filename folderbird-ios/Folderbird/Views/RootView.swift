import SwiftUI
import UIKit

/// Sign-in gate, then the layout that fits the window: a tab bar + pushed screens on a phone (and a narrow iPad
/// window), three columns on a regular-width iPad window. Both layouts read the same Workspace, so resizing a
/// window across the boundary (Stage Manager, Split View) keeps the selected device, folder, preview and console.
struct RootView: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var auth: AuthState
    @StateObject private var workspace = Workspace()
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var signedIn = Prefs.shared.isConfigured

    var body: some View {
        Group {
            if !signedIn {
                SignInView { signedIn = true }
            } else if hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad {
                RegularRootView()
            } else {
                CompactRootView()
            }
        }
        .environmentObject(workspace)
        .onChange(of: prefs.apiKey) { _, _ in signedIn = prefs.isConfigured }
        .onChange(of: signedIn) { _, now in if !now { workspace.reset() } }
        .onChange(of: scenePhase) { _, phase in
            // Back from the browser sign-in round trip or the share extension: re-read what was stored.
            if phase == .active {
                prefs.reload()
                signedIn = prefs.isConfigured
            }
        }
        .onReceive(auth.$expired) { hit in
            guard hit else { return }
            // An expired or revoked key (HTTP 401 from any call): drop straight to the sign-in screen with a
            // reason. Nothing to revoke — the server already said no.
            if prefs.isConfigured {
                prefs.signOut()
                prefs.signedOutReason = "Your sign-in has expired — please sign in again."
            }
            signedIn = false
            auth.expired = false
        }
    }
}

/// Phone layout: Devices / More tabs; browse, console and the editor push onto the Devices stack.
struct CompactRootView: View {
    @EnvironmentObject var workspace: Workspace
    @State private var tab = 0
    @State private var devicesPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $devicesPath) {
                DevicesView(mode: .list, path: $devicesPath)
            }
            .tabItem { Label("Devices", systemImage: "desktopcomputer") }
            .tag(0)

            NavigationStack { MoreView() }
                .tabItem { Label("More", systemImage: "line.3.horizontal") }
                .tag(1)
        }
        // Coming from the three-column layout (an iPad window narrowed): land on the device that was open.
        .onAppear {
            if devicesPath.isEmpty, let d = workspace.selectedDevice { devicesPath.append(d) }
        }
    }
}

/// iPad layout: devices in the sidebar, the folder listing in the middle, and previews / the editor / the console
/// in the detail column — so a file can be read or a command run while the listing stays in view.
struct RegularRootView: View {
    @EnvironmentObject var workspace: Workspace
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            DevicesView(mode: .sidebar, path: .constant(NavigationPath()))
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } content: {
            if let d = workspace.selectedDevice {
                BrowseView(model: workspace.model(for: d), layout: .regular)
                    .id(d.idStr)
            } else {
                ContentUnavailableView("Pick a device", systemImage: "desktopcomputer",
                                       description: Text("Choose a computer in the sidebar to browse its files."))
            }
        } detail: {
            if let d = workspace.selectedDevice {
                DetailPane(model: workspace.model(for: d))
                    .id(d.idStr)
            } else {
                ContentUnavailableView("Nothing open", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Previews, the text editor and the command console open in this column."))
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// The iPad detail column for one device: the editor wins over the console, which wins over a quick preview.
@MainActor
struct DetailPane: View {
    @ObservedObject var model: BrowseModel

    var body: some View {
        if let f = model.editing {
            FileViewerView(model: model, file: f, inDetailColumn: true).id(f.path)
        } else if model.consoleOpen {
            ConsoleView(model: model, inDetailColumn: true)
        } else if let f = model.previewing {
            PreviewPanel(model: model, file: f, docked: false).id(f.path)
        } else {
            ContentUnavailableView("No file selected", systemImage: "doc",
                                   description: Text("Tap a file to preview it here, or open the console to run commands on \(model.device.displayName)."))
        }
    }
}
