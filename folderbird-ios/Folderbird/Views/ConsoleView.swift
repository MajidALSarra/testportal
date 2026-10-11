import SwiftUI
import UIKit

/// The twin of the web's command console: runs cmd / PowerShell on the PC through the same /exec endpoint
/// (server waits up to ~45s; every command is audited server-side). Deliberately a fixed dark terminal look in
/// both themes. Commands the server classes as destructive are confirmed here first.
@MainActor
struct ConsoleView: View {
    @ObservedObject var model: BrowseModel
    var inDetailColumn = false

    @State private var cmd = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if model.consoleHistory.isEmpty {
                            Text("Commands run on \(model.device.displayName) and the output appears here.\nEach command gets up to 45 seconds.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(FB.terminalDim)
                        }
                        ForEach(model.consoleHistory) { e in
                            VStack(alignment: .leading, spacing: 4) {
                                Text((e.shell == "powershell" ? "PS> " : "C:\\> ") + e.cmd)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(FB.terminalPrompt)
                                    .textSelection(.enabled)
                                if let out = e.output {
                                    Text(out)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(e.error ? FB.terminalError : FB.terminalText)
                                        .textSelection(.enabled)
                                } else {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small).tint(FB.terminalDim)
                                        Text("running…").font(.system(size: 12, design: .monospaced)).foregroundStyle(FB.terminalDim)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(e.id)
                        }
                    }
                    .padding(12)
                }
                .background(FB.terminalBg)
                .onChange(of: model.consoleTick) { _, _ in
                    if let last = model.consoleHistory.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            VStack(spacing: 6) {
                Picker("Shell", selection: $model.consoleShell) {
                    Text("cmd").tag("cmd")
                    Text("PowerShell").tag("powershell")
                }
                .pickerStyle(.segmented)
                HStack(spacing: 8) {
                    TextField(model.consoleShell == "powershell" ? "Get-Process | Select -First 5" : "dir", text: $cmd)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.send)
                        .focused($focused)
                        .onSubmit { run() }
                    Button { run() } label: { Image(systemName: "paperplane.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.consoleBusy || cmd.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Run")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .navigationTitle("Console · \(model.device.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inDetailColumn {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { model.consoleOpen = false } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !model.consoleHistory.isEmpty {
                    Button { model.consoleClear() } label: { Image(systemName: "trash") }
                        .help("Clear output")
                }
            }
        }
        .alert("Run this on \(model.device.displayName)?", isPresented: confirmPresented, presenting: model.consoleConfirm) { p in
            Button("Yes, run it", role: .destructive) { model.consoleConfirmYes(p) }
            Button("No", role: .cancel) { model.consoleDecline(p) }
        } message: { p in
            Text("It can delete, move or change files or system state.\n\n\(p.cmd)\n(\(p.shell == "powershell" ? "PowerShell" : "cmd"))")
        }
        .onAppear { focused = true }
    }

    private var confirmPresented: Binding<Bool> {
        Binding(get: { model.consoleConfirm != nil },
                set: { shown in if !shown, let p = model.consoleConfirm { model.consoleDecline(p) } })
    }

    private func run() {
        let c = cmd.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty, !model.consoleBusy else { return }
        cmd = ""
        model.consoleRun(c)
    }
}
