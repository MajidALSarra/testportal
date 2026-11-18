import Foundation
import UIKit

/// Launch-environment hooks for the XCUITest screenshot run (FolderbirdUITests/ScreenshotTests.swift).
/// Inert unless the test runner sets FB_UITEST=1 — a normal launch never carries these variables, and nothing
/// here can be reached from outside the process.
///
///   FB_UITEST=1            turn the hooks on and disable UIKit animations (steadier screenshots)
///   FB_UITEST_RESET=1      start signed out with the default server and the system theme
///   FB_UITEST_BASEURL=…    prefill the server URL (the mock on 127.0.0.1, or a staging host)
///   FB_UITEST_APIKEY=…     start signed in with this key (the sign-in FORM is exercised by the tests that omit it)
enum UITestHooks {
    static var active: Bool { ProcessInfo.processInfo.environment["FB_UITEST"] == "1" }

    static func apply() {
        let env = ProcessInfo.processInfo.environment
        guard env["FB_UITEST"] == "1" else { return }
        MainActor.assumeIsolated { UIView.setAnimationsEnabled(false) }   // App.init runs on the main thread
        let prefs = Prefs.shared
        if env["FB_UITEST_RESET"] == "1" {
            prefs.signOut()
            prefs.signedOutReason = ""
            prefs.themeMode = "system"
            prefs.baseUrl = Prefs.defaultBase
        }
        if let b = env["FB_UITEST_BASEURL"], !b.trimmingCharacters(in: .whitespaces).isEmpty {
            prefs.baseUrl = Prefs.normalizeBase(b)
        }
        if let k = env["FB_UITEST_APIKEY"], !k.trimmingCharacters(in: .whitespaces).isEmpty {
            prefs.apiKey = k
        }
    }
}
