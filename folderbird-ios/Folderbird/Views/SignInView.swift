import SwiftUI

@MainActor
struct SignInView: View {
    @EnvironmentObject var prefs: Prefs
    let onSignedIn: () -> Void

    @State private var showKey = false
    @State private var base = Prefs.shared.baseUrl
    @State private var key = ""
    @State private var status: String?
    @State private var busy = false
    @State private var signedOutReason = ""
    @State private var safari: IdentifiableURL?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Spacer().frame(height: 48)
                BrandLogo(markSize: 46, textSize: 30)
                Text("Access your PC files from anywhere.")
                    .foregroundStyle(.secondary)
                if !signedOutReason.isEmpty {
                    Text(signedOutReason)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                Spacer().frame(height: 26)

                Button { startLogin() } label: {
                    Label("Sign in with Folderbird", systemImage: "person.crop.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)

                Button("Create an account") {
                    if let u = URL(string: prefs.normalizedBase + "/Account/Register") { safari = IdentifiableURL(url: u) }
                }
                .font(.subheadline)

                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    Text("or").font(.footnote).foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                }
                .padding(.vertical, 6)

                Button(showKey ? "Hide API key sign-in" : "Use an API key instead") { showKey.toggle() }
                    .font(.subheadline)

                if showKey {
                    VStack(spacing: 10) {
                        TextField("Server URL", text: $base)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("API key (fbk_…)", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(busy ? "Testing…" : "Save & connect") { saveKey() }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy)
                            .frame(maxWidth: .infinity)
                    }
                }
                if let s = status {
                    Text(s).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Spacer().frame(height: 20)
                Text("📍 Riyadh, Saudi Arabia").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 480)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            // Shown once, then cleared — the reason for an involuntary sign-out (expired / revoked key).
            signedOutReason = prefs.signedOutReason
            prefs.signedOutReason = ""
        }
        .sheet(item: $safari) { SafariView(url: $0.url) }
    }

    private func startLogin() {
        busy = true; status = nil
        Task {
            do {
                let k = try await AuthManager.signIn(prefs: prefs)
                prefs.apiKey = k
                onSignedIn()
            } catch let e {
                status = errorMessage(e)
            }
            busy = false
        }
    }

    private func saveKey() {
        let b = Prefs.normalizeBase(base)
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { status = "Enter an API key."; return }
        busy = true; status = nil
        Task {
            do {
                // Prove the key works before persisting anything.
                let devices = try await Api(base: b, key: k).devices()
                prefs.baseUrl = b
                prefs.apiKey = k
                status = "Connected — \(devices.count) device(s)."
                onSignedIn()
            } catch let e {
                status = "Failed: \(errorMessage(e))"
            }
            busy = false
        }
    }
}
