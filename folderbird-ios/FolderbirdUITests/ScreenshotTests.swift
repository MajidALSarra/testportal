import XCTest
import UIKit

/// Walks the app the way a person would and saves a PNG at every screen — the "show me it working" run.
///
/// Backend: by default the mock server (tools/mockserver.py) on 127.0.0.1:8787, which needs no credentials and no
/// real PC. With FB_TEST_MODE=real and FB_TEST_APIKEY (+ FB_TEST_BASEURL) it drives a real Folderbird server and a
/// real PC. The variables come from the test runner's environment — xcodebuild passes every TEST_RUNNER_* variable
/// through with the prefix removed — see .github/workflows/ios-ui-test.yml.
///
///   FB_TEST_MODE      mock (default) | real
///   FB_TEST_BASEURL   server URL (default http://127.0.0.1:8787)
///   FB_TEST_APIKEY    the key typed into the sign-in form (default: the mock's fbk_mock_… key)
///   FB_TEST_DEVICE    real mode: the PC to open, by its name on My Devices (default: the first online row)
///   FB_TEST_WRITES    1 = also create a test folder on the PC (default 1 for mock, 0 for real)
///   FB_SHOT_DIR       directory the PNGs are written to (they are also attached to the .xcresult)
///
/// The checks are deliberately soft (continueAfterFailure): a step that cannot find its screen records a failure
/// and the walk goes on, so one missing file never costs the rest of the screenshots.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment
    private static var shotCounter = 0

    private var isMock: Bool { env["FB_TEST_MODE"] != "real" }
    private var base: String { nonEmpty(env["FB_TEST_BASEURL"]) ?? "http://127.0.0.1:8787" }
    private var key: String { nonEmpty(env["FB_TEST_APIKEY"]) ?? (isMock ? "fbk_mock_0123456789abcdef0123456789abcdef" : "") }
    private var writes: Bool { (env["FB_TEST_WRITES"] ?? (isMock ? "1" : "0")) == "1" }
    private var shotDir: URL? { nonEmpty(env["FB_SHOT_DIR"]).map { URL(fileURLWithPath: $0, isDirectory: true) } }
    /// A device round trip on a real server takes 20-60 s; the mock answers at once.
    private var slow: TimeInterval { isMock ? 25 : 90 }
    /// XCUITest runs on the main thread; UIDevice is main-actor isolated in the SDK.
    private var pad: Bool { MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad } }
    private var idiom: String { pad ? "ipad" : "iphone" }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // The iPad screenshots show the three-column layout, which needs a regular-width window.
        if pad { XCUIDevice.shared.orientation = .landscapeLeft }
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    // MARK: - Tests

    /// Signed-out screens: the sign-in page, the API-key form, and what a refused key looks like.
    func test01_SignInScreens() throws {
        launch(reset: true)
        XCTAssertTrue(app.buttons["signin.pkce"].waitForExistence(timeout: 30), "sign-in screen")
        shot("signin")
        app.buttons["signin.toggleKey"].tap()
        XCTAssertTrue(app.secureTextFields["signin.key"].waitForExistence(timeout: 5), "API-key form")
        shot("signin-api-key-form")
        ensureBase()
        enter(app.secureTextFields["signin.key"], "fbk_wrong_key_000000000000000000")
        app.buttons["signin.save"].tap()
        XCTAssertTrue(waitStatus(containing: "Failed", slow), "a refused key is reported on the form")
        shot("signin-refused-key")
    }

    /// The whole signed-in journey: devices → add-device sheet → browse → previews (text, PDF, Office, image) →
    /// search → console, incl. the destructive-command confirmation → new folder → settings, theme → sign out.
    func test02_SignedInJourney() throws {
        try XCTSkipIf(key.isEmpty, "FB_TEST_APIKEY is not set for a real-server run")
        launch(reset: true)
        signInWithKey()
        guard waitForDevices() else { shot("devices-missing"); return }
        shot("devices")
        addDeviceSheet()
        if isMock { offlineDeviceToast() }
        guard openFirstOnlineDevice() else { shot("browse-missing"); return }
        browse()
        previews()          // text, PDF, Office in Documents; search there; then the image in Pictures
        console()
        if writes { newFolder() }
        if !pad { moreTab() }
        settingsAndTheme()
        signOut()
    }

    /// A launch that is already signed in (the key pre-seeded through the launch environment) — the state the app
    /// is in every day — plus the iPad in portrait.
    func test03_LaunchSignedIn() throws {
        try XCTSkipIf(key.isEmpty, "FB_TEST_APIKEY is not set for a real-server run")
        if pad { XCUIDevice.shared.orientation = .portrait }
        launch(reset: true, presetKey: key)
        XCTAssertTrue(waitForDevices(), "devices screen straight after launch")
        shot("launch-signed-in")
        if pad {
            _ = openFirstOnlineDevice()
            _ = app.buttons["Documents"].waitForExistence(timeout: slow) || app.buttons["This PC"].waitForExistence(timeout: slow)
            shot("ipad-portrait-browse")
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    // MARK: - Launch / sign-in

    private func launch(reset: Bool, presetKey: String? = nil) {
        app.launchEnvironment["FB_UITEST"] = "1"
        app.launchEnvironment["FB_UITEST_RESET"] = reset ? "1" : "0"
        app.launchEnvironment["FB_UITEST_BASEURL"] = base
        if let k = presetKey { app.launchEnvironment["FB_UITEST_APIKEY"] = k }
        app.launch()
    }

    /// The server field is prefilled by the launch hook; retype it only if that did not happen.
    private func ensureBase() {
        let field = app.textFields["signin.base"]
        guard field.waitForExistence(timeout: 5) else { XCTFail("server URL field"); return }
        let current = (field.value as? String ?? "").trimmingCharacters(in: .whitespaces)
        if current != base { enter(field, base, clear: true) }
    }

    private func signInWithKey() {
        XCTAssertTrue(app.buttons["signin.toggleKey"].waitForExistence(timeout: 30), "sign-in screen")
        app.buttons["signin.toggleKey"].tap()
        ensureBase()
        enter(app.secureTextFields["signin.key"], key)
        shot("signin-key-entered")
        app.buttons["signin.save"].tap()
    }

    @discardableResult
    private func waitForDevices() -> Bool {
        let ok = app.buttons["devices.settings"].waitForExistence(timeout: slow)
        XCTAssertTrue(ok, "devices screen after sign-in")
        guard ok else { return false }
        let row = deviceRow().waitForExistence(timeout: slow)
        XCTAssertTrue(row, "at least one device row")
        return row
    }

    // MARK: - Devices

    private func deviceRow(online: Bool? = nil) -> XCUIElement {
        var prefix = "device.row."
        if let o = online { prefix += (o ? "online." : "offline.") }
        return app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    private func addDeviceSheet() {
        app.buttons["devices.add"].tap()
        let shown = app.navigationBars["Add a device"].waitForExistence(timeout: 10)
        XCTAssertTrue(shown, "add-device sheet")
        guard shown else { return }
        _ = waitText(containing: "device code", slow)      // the code, or "doesn't need a device code"
        shot("add-device")
        app.navigationBars["Add a device"].buttons["Done"].tap()
    }

    private func offlineDeviceToast() {
        let row = deviceRow(online: false)
        guard row.waitForExistence(timeout: 5) else { return }
        row.tap()
        _ = waitText(containing: "is offline", 5)
        shot("device-offline-toast")
        Thread.sleep(forTimeInterval: 3)                     // let the toast go before the next screen
    }

    @discardableResult
    private func openFirstOnlineDevice() -> Bool {
        var row = deviceRow(online: true)
        if let name = nonEmpty(env["FB_TEST_DEVICE"]), app.staticTexts[name].waitForExistence(timeout: 5) {
            row = app.staticTexts[name]
        }
        let found = row.waitForExistence(timeout: slow)
        XCTAssertTrue(found, "an online device to open")
        guard found else { return false }
        row.tap()
        // The browse toolbar is up once the device screen (phone) / content column (iPad) is showing.
        let ok = app.buttons["browse.console"].waitForExistence(timeout: slow)
        XCTAssertTrue(ok, "browse toolbar")
        return ok
    }

    // MARK: - Browse / preview / search

    private func browse() {
        // Landing = the home folder (Documents, Pictures…), or "This PC" (the drives) when the home can't be resolved.
        let landed = app.buttons["Documents"].waitForExistence(timeout: slow)
            || app.staticTexts["Documents"].waitForExistence(timeout: 5)
            || app.buttons["This PC"].waitForExistence(timeout: 5)
        XCTAssertTrue(landed, "landed on the home folder or on This PC")
        shot("browse-home")
        if open(folder: "Documents") {
            _ = app.staticTexts["notes.txt"].waitForExistence(timeout: slow) || app.staticTexts["Empty folder"].waitForExistence(timeout: 5)
            shot("browse-documents")
        }
    }

    /// Folder rows are buttons on the phone and table rows on the iPad; the name text is tappable in both.
    private func open(folder name: String) -> Bool {
        let b = app.buttons[name].firstMatch
        if b.waitForExistence(timeout: 5) { b.tap(); return true }
        let t = app.staticTexts[name].firstMatch
        if t.waitForExistence(timeout: 5) { t.tap(); return true }
        activity("no folder \(name) on this PC — skipped")
        return false
    }

    private func previews() {
        preview("notes.txt", expectText: "Folderbird", as: "text")
        preview("Annual-Report-2026.pdf", expectText: "page", as: "pdf")
        preview("Q3-Sales-Report.xlsx", expectText: nil, as: "office")
        closePreviewIfDocked()
        search()            // "report" scoped to the current folder — Documents has four matches
        // The image lives in Pictures: up one level, then into Pictures.
        if goUp() {
            if app.buttons["Pictures"].firstMatch.waitForExistence(timeout: slow) || app.staticTexts["Pictures"].firstMatch.waitForExistence(timeout: 5) {
                _ = open(folder: "Pictures")
                preview("sunset.png", expectText: nil, as: "image")
                closePreviewIfDocked()
            }
        }
    }

    /// Taps a file row and waits for its preview: the panel docked under the list on the phone, the detail column
    /// on the iPad. expectText nil = wait for an image / web view / PDF to show instead.
    private func preview(_ name: String, expectText: String?, as tag: String) {
        let row = app.staticTexts[name].firstMatch
        guard row.waitForExistence(timeout: 5) else { activity("no \(name) on this PC — skipped"); return }
        reveal(row)
        row.tap()
        // The panel (docked on the phone, the detail column on the iPad) is up once its Close button exists.
        XCTAssertTrue(app.buttons["Close preview"].waitForExistence(timeout: 10), "preview panel for \(name)")
        if let e = expectText {
            XCTAssertTrue(waitText(containing: e, slow), "preview of \(name) shows '\(e)'")
        } else if tag == "office" {
            // The web view exists before its page has rendered (the WebKit process starts cold on a fresh
            // simulator); wait for text inside it, then a beat for layout.
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: slow), "web preview of \(name)")
            let rendered = app.webViews.staticTexts.firstMatch.waitForExistence(timeout: slow)
            XCTAssertTrue(rendered, "the server preview page rendered text for \(name)")
            Thread.sleep(forTimeInterval: isMock ? 2 : 6)
        } else {
            _ = app.staticTexts["Loading preview…"].waitForExistence(timeout: 2)
            let deadline = Date().addingTimeInterval(slow)
            while app.staticTexts["Loading preview…"].exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
            Thread.sleep(forTimeInterval: 1.5)                 // image decode
        }
        shot("preview-\(tag)")
        if !pad { closePreviewIfDocked() }
    }

    /// Up one folder: the toolbar button on the iPad, the actions-menu item on the phone.
    private func goUp() -> Bool {
        if app.buttons["browse.up"].exists { app.buttons["browse.up"].tap(); return true }
        openActionsMenu()
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Up one folder")).firstMatch
        guard item.waitForExistence(timeout: 5) else { return false }
        item.tap()
        return true
    }

    /// The toolbar Menu reports itself as not hittable to XCUITest (a plain tap fails with "failed to scroll to
    /// visible"), so it is opened by a tap at its centre, which does not go through the hittability check.
    private func openActionsMenu() {
        let menu = app.buttons["browse.add"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "actions menu button")
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func closePreviewIfDocked() {
        let close = app.buttons["Close preview"]
        if close.exists && close.isHittable { close.tap() }
    }

    private func search() {
        app.buttons["browse.search"].tap()
        let field = app.searchFields.firstMatch
        let shown = field.waitForExistence(timeout: 10)
        XCTAssertTrue(shown, "search field")
        guard shown else { return }
        field.tap()
        field.typeText("report\n")
        XCTAssertTrue(waitText(containing: "result", slow) || waitText(containing: "No matches", 5), "search results")
        shot("search-results")
        let cancel = app.buttons["Cancel"]
        if cancel.exists { cancel.tap() } else { app.buttons["browse.search"].tap() }
        _ = app.buttons["browse.console"].waitForExistence(timeout: 10)
    }

    // MARK: - Console

    private func console() {
        app.buttons["browse.console"].tap()
        let input = app.textFields["console.input"]
        let shown = input.waitForExistence(timeout: 15)
        XCTAssertTrue(shown, "console")
        guard shown else { return }
        shot("console-empty")
        run(command: "hostname")
        XCTAssertTrue(waitText(containing: isMock ? "HOME-DESKTOP" : "hostname", slow), "console output")
        waitUntilNotRunning()
        shot("console-output")
        // A command the server classes as destructive is refused with 409 and confirmed in the app first.
        run(command: isMock ? "del C:\\Users\\Alex\\Documents\\old.tmp" : "del %TEMP%\\folderbird-ios-uitest.tmp")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: slow), "destructive-command confirmation")
        shot("console-destructive-confirm")
        if alert.exists { alert.buttons["No"].tap() }
        _ = waitText(containing: "not run", 10)
        shot("console-declined")
        // Back to the folder listing.
        if pad {
            app.buttons["Close"].firstMatch.tap()
        } else {
            back()
            _ = app.buttons["browse.console"].waitForExistence(timeout: 10)
        }
    }

    private func run(command: String) {
        let input = app.textFields["console.input"]
        input.tap()
        input.typeText(command)
        app.buttons["console.send"].tap()
    }

    private func waitUntilNotRunning() {
        let deadline = Date().addingTimeInterval(slow)
        while app.staticTexts["running…"].exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
    }

    // MARK: - New folder

    private func newFolder() {
        let name = "From the \(pad ? "iPad" : "iPhone")"
        openActionsMenu()
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "New folder")).firstMatch
        guard item.waitForExistence(timeout: 5) else { XCTFail("New folder menu item"); return }
        item.tap()
        let alert = app.alerts["New folder"]
        guard alert.waitForExistence(timeout: 5) else { XCTFail("New folder dialog"); return }
        alert.textFields.firstMatch.tap()
        alert.textFields.firstMatch.typeText(name)
        shot("new-folder-dialog")
        alert.buttons["Create"].tap()
        let created = app.buttons[name].waitForExistence(timeout: slow) || app.staticTexts[name].waitForExistence(timeout: 5)
        XCTAssertTrue(created, "the new folder appears in the listing")
        shot("browse-new-folder")
    }

    // MARK: - More / settings / sign-out

    private func moreTab() {
        back()                                                  // from the device screen to the list
        _ = app.buttons["devices.settings"].waitForExistence(timeout: 10)
        let more = app.tabBars.buttons["More"]
        guard more.waitForExistence(timeout: 5) else { XCTFail("More tab"); return }
        more.tap()
        _ = app.staticTexts["Pricing & plans"].waitForExistence(timeout: 5)
        shot("more")
        app.tabBars.buttons["Devices"].tap()
    }

    private func settingsAndTheme() {
        guard app.buttons["devices.settings"].waitForExistence(timeout: 10) else { XCTFail("devices toolbar"); return }
        app.buttons["devices.settings"].tap()
        guard app.buttons["settings.test"].waitForExistence(timeout: 10) else { XCTFail("settings sheet"); return }
        shot("settings")
        app.buttons["settings.test"].tap()
        let result = app.staticTexts["settings.testResult"]
        _ = result.waitForExistence(timeout: slow)
        let deadline = Date().addingTimeInterval(slow)
        while !(result.label.contains("Connected") || result.label.hasPrefix("✗")) && Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(result.label.contains("Connected"), "connection test: \(result.label)")
        shot("settings-connection-test")
        app.buttons["Dark"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)
        shot("settings-dark")
        app.navigationBars.buttons["Done"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)
        shot("devices-dark")
        app.buttons["devices.settings"].tap()
        _ = app.buttons["settings.test"].waitForExistence(timeout: 10)
        app.buttons["System"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)
    }

    private func signOut() {
        if !app.buttons["settings.signout"].exists {
            app.buttons["devices.settings"].tap()
        }
        guard app.buttons["settings.signout"].waitForExistence(timeout: 10) else { XCTFail("sign-out button"); return }
        app.buttons["settings.signout"].tap()
        XCTAssertTrue(app.buttons["signin.pkce"].waitForExistence(timeout: 20), "back on the sign-in screen")
        shot("signed-out")
    }

    // MARK: - Helpers

    private func back() {
        let b = app.navigationBars.firstMatch.buttons.firstMatch
        if b.exists { b.tap() }
    }

    /// Scroll a list row into view (the docked preview panel hides the lower rows on the phone).
    private func reveal(_ e: XCUIElement) {
        var tries = 0
        while e.exists && !e.isHittable && tries < 4 {
            app.swipeUp()
            tries += 1
        }
    }

    private func enter(_ field: XCUIElement, _ text: String, clear: Bool = false) {
        guard field.waitForExistence(timeout: 5) else { XCTFail("field to type into"); return }
        field.tap()
        if clear, let v = field.value as? String, !v.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
        }
        field.typeText(text)
    }

    private func waitText(containing s: String, _ t: TimeInterval) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch.waitForExistence(timeout: t)
    }

    private func waitStatus(containing s: String, _ t: TimeInterval) -> Bool {
        let status = app.staticTexts["signin.status"]
        let deadline = Date().addingTimeInterval(t)
        while Date() < deadline {
            if status.exists && status.label.localizedCaseInsensitiveContains(s) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func activity(_ note: String) {
        XCTContext.runActivity(named: note) { _ in }
    }

    /// Full-screen PNG: attached to the result bundle and, when FB_SHOT_DIR is set, written to disk as
    /// <dir>/<idiom>/<NN>-<name>.png so the workflow can commit it without opening the bundle.
    @discardableResult
    private func shot(_ name: String) -> XCUIScreenshot {
        let s = XCUIScreen.main.screenshot()
        Self.shotCounter += 1
        let file = String(format: "%02d-%@", Self.shotCounter, name)
        let a = XCTAttachment(screenshot: s)
        a.name = "\(idiom)-\(file)"
        a.lifetime = .keepAlways
        add(a)
        if let dir = shotDir {
            let sub = dir.appendingPathComponent(idiom, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
                try s.pngRepresentation.write(to: sub.appendingPathComponent(file + ".png"))
            } catch {
                activity("could not write \(file).png: \(error)")
            }
        }
        return s
    }
}
