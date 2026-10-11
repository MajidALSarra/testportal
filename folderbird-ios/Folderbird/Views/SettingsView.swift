import SwiftUI

/// Account & settings: the key in use, re-sign-in / sign-out, theme, and the server URL with a connection test.
@MainActor
struct SettingsView: View {
    var inSheet = false

    @EnvironmentObject var prefs: Prefs
    @Environment(\.dismiss) private var dismiss
    @State private var base = Prefs.shared.baseUrl
    @State private var testResult: String?
    @State private var testing = false
    @State private var reauthError: String?
    @State private var reauthing = false

    private var keyMask: String {
        let k = prefs.apiKey
        if k.isEmpty { return "(none)" }
        return k.count > 14 ? "\(k.prefix(12))…\(k.suffix(4))" : k
    }

    var body: some View {
        Form {
            Section("Account") {
                Text("Signed in")
                LabeledContent("Key", value: keyMask)
                if !prefs.keyExpiresAt.isEmpty {
                    LabeledContent("Expires", value: "\(prefs.keyExpiresAt.prefix(10)) (re-sign in any time to renew)")
                }
                HStack(spacing: 10) {
                    Button(reauthing ? "Signing in…" : "Re-sign in") { reauth() }.buttonStyle(.bordered).disabled(reauthing)
                    Button("Sign out", role: .destructive) { signOut() }.buttonStyle(.borderedProminent).tint(.red)
                }
                if let e = reauthError { Text(e).font(.footnote).foregroundStyle(.red) }
            }
            Section("Appearance") {
                Picker("Theme", selection: $prefs.themeMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Section("Connection") {
                TextField("Server URL", text: $base)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                HStack(spacing: 10) {
                    Button("Save") {
                        prefs.baseUrl = Prefs.normalizeBase(base)
                        base = prefs.baseUrl
                        testResult = "Saved."
                    }
                    .buttonStyle(.borderedProminent)
                    Button(testing ? "Testing…" : "Test connection") { test() }
                        .buttonStyle(.bordered)
                        .disabled(testing)
                }
                if let t = testResult { Text(t).font(.footnote) }
            }
            Section {
                Text("Folderbird • v\(appVersion())").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Account & settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func test() {
        prefs.baseUrl = Prefs.normalizeBase(base)
        base = prefs.baseUrl
        testing = true; testResult = nil
        Task {
            do {
                let ds = try await Api(prefs).devices()
                if ds.isEmpty {
                    testResult = "✓ Connected, but 0 devices came back — the key reached the server yet returned no devices (scope or account mismatch)."
                } else {
                    testResult = "✓ Connected. Devices: \(ds.count)\n" + ds.map { "• \($0.displayName) (\($0.status ?? "?"))" }.joined(separator: "\n")
                }
            } catch let e {
                testResult = "✗ \(errorMessage(e))"
            }
            testing = false
        }
    }

    private func reauth() {
        guard !reauthing else { return }
        reauthing = true; reauthError = nil
        Task {
            do {
                let k = try await AuthManager.signIn(prefs: prefs)
                prefs.apiKey = k
            } catch let e {
                reauthError = errorMessage(e)
            }
            reauthing = false
        }
    }

    /// Read the key BEFORE clearing it; the revoke runs in the background and the UI never waits on it.
    private func signOut() {
        AuthManager.revokeAsync(baseUrl: prefs.baseUrl, key: prefs.apiKey)
        prefs.signOut()
        if inSheet { dismiss() }
    }
}
