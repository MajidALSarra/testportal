import SwiftUI
import UIKit

enum DevicesMode { case list, sidebar }

/// Phone-only pushed screens that start from the device list.
enum DeviceRoute: Hashable {
    case console(Device)
}

/// Every connected computer with its live status. `.list` is the phone's first screen (rows push the browser);
/// `.sidebar` is the iPad's first column (rows select the device for the other two columns).
@MainActor
struct DevicesView: View {
    let mode: DevicesMode
    @Binding var path: NavigationPath

    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var workspace: Workspace
    @State private var loading = true
    @State private var error: String?
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var toast: String?
    @State private var safari: IdentifiableURL?
    @State private var appeared = false

    var body: some View {
        Group {
            if loading && workspace.devices.isEmpty {
                CenterProgress()
            } else if let e = error, workspace.devices.isEmpty {
                ErrorBox(message: e, onRetry: { Task { await reload() } }, secondary: ("Settings", { showSettings = true }))
            } else if workspace.devices.isEmpty {
                emptyState
            } else if mode == .sidebar {
                sidebarList
            } else {
                compactList
            }
        }
        .navigationDestination(for: Device.self) { d in
            BrowseView(model: workspace.model(for: d), layout: .compact)
        }
        .navigationDestination(for: DeviceRoute.self) { route in
            switch route {
            case .console(let d): ConsoleView(model: workspace.model(for: d))
            }
        }
        .navigationTitle(mode == .sidebar ? "Devices" : "")
        .toolbar {
            if mode == .list {
                ToolbarItem(placement: .principal) { BrandLogo(markSize: 26, textSize: 19) }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .help("Add a device")
                // ⇧⌘R on iPad, where ⌘R belongs to the folder listing shown beside this sidebar.
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: mode == .sidebar ? EventModifiers([.command, .shift]) : EventModifiers.command)
                    .help("Refresh devices")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Account & settings")
            }
        }
        .sheet(isPresented: $showAdd) { AddDeviceSheet() }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView(inSheet: true) } }
        .sheet(item: $safari) { SafariView(url: $0.url) }
        .task { await reload() }
        // Back from the browser / console on the phone: refresh the statuses, as Android does on each show.
        .onAppear {
            if appeared && mode == .list { Task { await reload() } }
            appeared = true
        }
        .toast($toast)
    }

    // MARK: - Lists

    private var compactList: some View {
        List {
            ForEach(workspace.devices) { d in
                if d.isOnline {
                    NavigationLink(value: d) {
                        DeviceRow(device: d, onConsole: { openConsole(d) })
                    }
                } else {
                    DeviceRow(device: d)
                        .opacity(0.5)
                        .contentShape(Rectangle())
                        .onTapGesture { toast = offlineMessage(d) }
                }
            }
            addRow
        }
        .listStyle(.plain)
        .refreshable { await reload() }
    }

    private var sidebarList: some View {
        List(selection: $workspace.selectedDeviceId) {
            Section("Devices") {
                ForEach(workspace.devices) { d in
                    if d.isOnline {
                        // No gesture on selectable rows: a tap gesture would swallow the touch before the
                        // List selection (and so the other two columns) could react.
                        DeviceRow(device: d, onConsole: { openConsole(d) })
                            .tag(d.idStr)
                    } else {
                        DeviceRow(device: d)
                            .tag(d.idStr)
                            .selectionDisabled(true)
                            .opacity(0.5)
                            .onTapGesture { toast = offlineMessage(d) }
                    }
                }
                addRow
            }
            Section("More") {
                MoreLinkRows(links: MoreLinks.account + MoreLinks.folderbird + MoreLinks.legal,
                             onSettings: { showSettings = true },
                             onOpen: { safari = IdentifiableURL(url: $0) })
            }
        }
        .listStyle(.sidebar)
        .refreshable { await reload() }
    }

    private var addRow: some View {
        Button { showAdd = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus").foregroundStyle(FB.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a device").fontWeight(.medium).foregroundStyle(FB.blue)
                    Text("Connect another PC to this account").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No devices returned for your account.").font(.headline)
            Text("If you have devices, this usually means the sign-in key needs re-checking.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await reload() } }.buttonStyle(.borderedProminent).padding(.top, 8)
            Button("Open Settings · Test connection") { showSettings = true }.buttonStyle(.bordered)
            // A brand-new account has zero devices — adding one IS the next step, so offer it here too.
            Button { showAdd = true } label: { Label("Add a device", systemImage: "plus") }.buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func reload() async {
        loading = true; error = nil
        do {
            workspace.devices = try await Api(prefs).devices()
        } catch let e {
            error = errorMessage(e)
            // A failed refresh with a list already on screen keeps the list but says so.
            if !workspace.devices.isEmpty { toast = "Couldn't refresh devices: \(errorMessage(e))" }
        }
        loading = false
    }

    private func offlineMessage(_ d: Device) -> String {
        "\(d.displayName) is offline — open the Folderbird app on that PC first."
    }

    /// Same pair of actions the web's device card leads with: console + browse.
    private func openConsole(_ d: Device) {
        workspace.selectedDeviceId = d.idStr
        if mode == .list {
            path.append(DeviceRoute.console(d))        // Back returns to this list, not to a folder listing
        } else {
            workspace.model(for: d).openConsole()      // iPad: the detail column (asks before dropping edits)
        }
    }
}

struct DeviceRow: View {
    let device: Device
    var onConsole: (() -> Void)? = nil

    // Colour carries the state at a glance: green online, amber laggy, grey offline.
    private var tint: Color { !device.isOnline ? Color.secondary : (device.isSlow ? FB.slow : FB.online) }

    private var statusText: String {
        guard device.isOnline else { return "○ offline — can't browse until it's online" }
        let seen = (device.lastSeen ?? "").trimmingCharacters(in: .whitespaces)
        return (device.isSlow ? "◐ " : "● ") + device.statusLabel + (seen.isEmpty ? "" : " · \(seen)")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer").font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName).fontWeight(.semibold).foregroundStyle(.primary)
                Text(statusText)
                    .font(.caption)
                    .fontWeight(device.isOnline ? .semibold : .regular)
                    .foregroundStyle(tint)
            }
            Spacer()
            if let c = onConsole {
                Button(action: c) { Image(systemName: "terminal").foregroundStyle(FB.blue) }
                    .buttonStyle(.borderless)
                    .help("Command console")
            }
        }
        .contentShape(Rectangle())
    }
}

/// "Add a device": the steps to connect a new PC. The one-time code is fetched when the sheet opens, and the
/// server says whether this account even needs one (only two-factor accounts are ever asked at device sign-in).
@MainActor
struct AddDeviceSheet: View {
    @EnvironmentObject var prefs: Prefs
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var minutes = 10
    @State private var required = true
    @State private var busy = true
    @State private var codeError: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("1.  On the PC, download the Folderbird app from folderbird.com/Download and install it.")
                    Text("2.  Sign in there with your Folderbird email and password.")
                    Spacer().frame(height: 6)
                    if busy {
                        HStack(spacing: 10) { ProgressView(); Text("Checking your account…") }
                    } else if let c = code, !required {
                        // No 2FA on the account → the PC will never ask for a code. Say so instead of showing one.
                        Text("✓ That's it — your account doesn't need a device code. The PC appears in your list as soon as it signs in.")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(c.isEmpty)
                    } else if let c = code {
                        Text("3.  Your account has two-factor sign-in, so the PC will ask for this device code:")
                        HStack {
                            Text(c)
                                .font(.system(.title2, design: .monospaced).weight(.bold))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = c
                                copied = true
                            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                            .buttonStyle(.bordered)
                            .help("Copy code")
                        }
                        Text("Expires in \(minutes) minutes.").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button("Try again") { Task { await fetch() } }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                    if let e = codeError {
                        Text(e).font(.footnote).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Add a device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { await fetch() }
    }

    private func fetch() async {
        busy = true; codeError = nil
        do {
            let r = try await Api(prefs).deviceCode()
            code = r.code
            minutes = r.minutes ?? 10
            required = r.required ?? true
        } catch let e {
            // A key minted before this feature lacks the enroll permission — the fix is a fresh sign-in.
            codeError = (e as? ApiError)?.status == 403
                ? "This sign-in is missing the new permission — sign out and back in (More → Account & settings), then try again."
                : errorMessage(e)
        }
        busy = false
    }
}
