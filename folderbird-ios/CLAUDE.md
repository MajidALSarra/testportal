# Folderbird iOS — project guide

Read `README.md` first: it documents the features, the iPad layout, how previews work and the build.

- **Build**: XcodeGen (`project.yml`) → `./bootstrap.sh`. The `.xcodeproj`, both `Info.plist`s and both
  `.entitlements` files are generated and git-ignored; change `project.yml`, never the generated files.
- **Two targets, one code base**: `Shared/` compiles into the app and the share extension and must stay
  extension-safe (no `UIApplication`). `Folderbird/` is the app, `ShareExtension/` the share sheet.
- **Behaviour contract = the Android app** (`MajidALSarra/Folderbird-Android`): screens, texts, error handling
  (401 → sign-in with reason; 409 destructive-command confirm; 504 texts), the preview cache rules and the share flow
  mirror `MainActivity.kt` / `ShareActivity.kt`. When Android changes, port the change here.
- **API**: `/api/v1` with a scoped API key (`Shared/Api.swift`); PKCE sign-in via `/app/authorize` + `/app/token`
  (`Folderbird/App/Auth.swift`); the server is `MajidALSarra/folderbird-web`.
- **State**: `Workspace` (one per window) + `BrowseModel` (one per device) in `Folderbird/App/Workspace.swift` are
  the single source of truth for both the iPhone layout (`CompactRootView`) and the iPad layout (`RegularRootView`).
- **Compile constraints**: iOS 17 deployment target, Swift 5 language mode, strict concurrency minimal. View
  structs that call into the `@MainActor` models from helper methods are themselves marked `@MainActor` so they
  also build on the iOS 17 SDK (Xcode 15). Never put `await` inside a `??` right-hand side (autoclosure).
- **Privacy manifests**: `Folderbird/Resources/PrivacyInfo.xcprivacy` and `ShareExtension/PrivacyInfo.xcprivacy`
  declare the required-reason APIs in use (app-group `UserDefaults` 1C8F.1 + CA92.1, file timestamps C617.1). Adding a
  disk-space, boot-time or keyboard-list API means adding its category there, or App Store Connect rejects the build.
- **`NSLock` never inside an `async` body**: Swift warns (`lock is unavailable from asynchronous contexts`) and
  Swift 6 refuses. Keep every locked section in a synchronous helper, as `PreviewCache.fetch` does.
- **CI**: `.github/workflows/ios-build.yml` builds the simulator app unsigned on every push to `main`, asserts both
  targets were built, the extension embedded and both privacy manifests present, prints the Swift warning count
  (keep it at 0) and uploads the app plus the full xcodebuild log.
