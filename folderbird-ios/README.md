# Folderbird for iOS & iPadOS

The native Apple companion for **Folderbird** — browse your computers, search and preview their files, download and
upload, run console commands, and share files from any app straight to a folder on your PC. It is the iOS twin of
the [Android app](https://github.com/MajidALSarra/Folderbird-Android): same features, same `/api/v1` REST API, same
look — plus a layout that uses the whole screen on an iPad.

## Features (parity with Android)

- **Sign in with Folderbird** — a browser-based PKCE login (`ASWebAuthenticationSession` → `/app/authorize` →
  `/app/token`), so your password never touches the app. An API-key option is still available.
- **Encrypted credentials** — the API key lives in the Keychain (shared with the share extension through a
  keychain access group); settings live in an App Group.
- **Device list** — live status (green online, amber slow, grey offline), **Add a device** with the one-time
  enrollment code (hidden for accounts without two-factor sign-in), refresh, settings.
- **Device browser** — lands on the home folder; **This PC** drive picker with free/total space; tappable
  breadcrumbs; special folders (Desktop, Documents, Downloads, Pictures) pinned on top with the website's icons and
  colours; colourful file-type icons; Linux-agent paths (`/root/…`) handled alongside Windows paths.
- **Search** — per device (`/search`), scoped to the current folder, optionally inside file contents.
- **Preview** — text, images (decoded at a bounded size so a 40 MP photo can't exhaust memory), PDF (full document,
  not just page 1), and Office files through the server's tokenized `/preview/{token}` page in a web view that follows
  the app's theme. Docked, resizable bottom panel on iPhone; the detail column on iPad.
- **Open / edit** — a full-screen text editor that saves back to the PC (`/files/write`), plus Open (Quick Look)
  and **Save to this device** (lands in Files › On My iPad › Folderbird, with Share offered as a button).
- **Upload** from the Files picker or from Photos (photos and videos keep their original names), **New folder**, and transfer progress with the honest two-phase bar
  (phone → server, then server → PC).
- **Command console** — cmd / PowerShell through `/exec`; commands the server classes as destructive (409
  `confirm_destructive_required`) are confirmed on the device first, exactly like Android.
- **Share extension** — **Folderbird** appears in every app's share sheet (the iOS twin of Android's "Send to a
  Folderbird device"): one item or a
  multi-selection, online devices only, home folder by default, a folder picker, recent-folder chips, sequential
  uploads with progress, and a success / partly / failed result screen.
- **Account & settings** — key and expiry, re-sign-in, sign out (revokes the key server-side), theme
  (system / light / dark), server URL with a connection test.
- **More** — the website's account, pricing, contact and legal pages opened in-app, always current.
- **Expired keys** — any HTTP 401 drops the app to the sign-in screen with a reason (keys expire after 90 days).

## iPad: extended screen utilisation

On a regular-width window the app runs as a three-column `NavigationSplitView`:

| Column | Shows |
|---|---|
| Sidebar | Your devices (select to browse; console shortcut on each row) and the More links |
| Content | A desktop-class **file table** (Name / Size / Modified, sortable by column) with breadcrumbs, search and the upload / new-folder menu |
| Detail | The file preview, the text editor **or the console** — so you can run commands or read a file while the listing stays in view |

Also on iPad: keyboard shortcuts (⌘R refresh the folder, ⇧⌘R refresh devices, ⌘F search, ⌘↑ up a folder, ⌘U upload, ⇧⌘N new folder, ⌘T console,
⌘S save in the editor, ⌘, settings), **drag & drop** files from the Files app onto a folder listing to upload them,
right-click / long-press context menus on files, pointer hover tooltips, **multiple windows** (open two devices side
by side in Split View or Stage Manager), and all orientations. Resizing a window across the compact/regular boundary
keeps your place — the selected device, folder, preview and console state live in one shared `Workspace`.

## Build

Requirements: a Mac with Xcode 15 or newer (CI uses Xcode 16) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The Xcode project is generated from `project.yml` and is not committed.

```bash
./bootstrap.sh          # installs XcodeGen via Homebrew if needed, runs `xcodegen generate`, opens the project
```

Then put your Apple Developer **Team ID** in `project.yml` (`settings.base.DEVELOPMENT_TEAM`) and re-run `./bootstrap.sh`;
it applies to both targets. (A Team picked in Xcode's Signing & Capabilities is written into the generated, git-ignored
`.xcodeproj` and is lost on the next generate.)
The App Group (`group.com.folderbird.companion`) and Keychain Sharing (`$(AppIdentifierPrefix)com.folderbird.companion`)
capabilities are declared in the generated entitlements; Xcode registers them with your team automatically. Run on a
device or the Simulator with ⌘R. (Signed builds are needed for the share extension and the shared keychain to work on a
real device; on the Simulator the key falls back to an ungrouped keychain item.)

Bundle ids: `com.folderbird.companion` (app) and `com.folderbird.companion.share` (extension); deployment target iOS 17.

### CI

Every push to `main` runs `.github/workflows/ios-build.yml`: XcodeGen → `xcodebuild` for the iOS Simulator, unsigned
(no Apple Developer account needed), and attaches `Folderbird-simulator.zip` as a workflow artifact. Drag the `.app`
inside it onto a booted Simulator to install. TestFlight / App Store builds need signing in Xcode.

## Project layout

```
project.yml                      # XcodeGen spec: app + share extension, entitlements, Info.plist keys
bootstrap.sh                     # generate the .xcodeproj (and open it)
Shared/                          # compiled into BOTH targets (extension-safe: no UIApplication)
  Api.swift                      # /api/v1 models (lenient decoding) + client, errors, AuthState (401 → sign-in)
  Prefs.swift                    # settings in the App Group UserDefaults; API key via Keychain
  Keychain.swift                 # shared keychain access group with an ungrouped fallback for unsigned builds
  Transfers.swift                # streaming download / multipart upload with progress (URLSession delegates)
  PreviewCache.swift             # the one-entry on-disk cache of the file the preview just pulled
  PathUtil.swift                 # Windows + Linux path helpers, breadcrumbs, sizes
  Brand.swift                    # brand colours, special-folder icons, file-type icons/colours
  UIBits.swift                   # progress / error / empty boxes, breadcrumb bar
Folderbird/                      # the app
  App/FolderbirdApp.swift        # entry point, theme, URL handling
  App/Auth.swift                 # PKCE + ASWebAuthenticationSession + /app/token + /app/revoke
  App/Workspace.swift            # Workspace (per window) + BrowseModel (per device): the single source of truth
  Views/RootView.swift           # sign-in gate; CompactRootView (tabs) / RegularRootView (3 columns) / DetailPane
  Views/SignInView.swift, DevicesView.swift, BrowseView.swift, FolderTable.swift (iPad), PreviewPanel.swift,
        FileViewerView.swift, ConsoleView.swift, SettingsView.swift, MoreView.swift, Components.swift
  Resources/Assets.xcassets      # AppIcon (rendered from the brand vector), FbMark (SVG, light + dark), AccentColor
ShareExtension/                  # the share-sheet extension (Android's "Send to a Folderbird device")
  ShareViewController.swift      # entry point: collects the shared items, hosts the SwiftUI flow
  SharedPayload.swift            # NSItemProvider → files / text, staged one at a time right before upload
  ShareRootView.swift            # device + folder choice, recent folders, sequential uploads, result screen
  FolderPickerView.swift         # This PC → drives → folders → "Upload here"
.github/workflows/ios-build.yml  # simulator build on every push
```

## How previews work (read before changing them)

Same as on Android: **every byte the app shows is fetched whole, and the device does all the rendering. The server
resizes, transcodes and thumbnails nothing.** The path is `PC → Azure Blob → server → device`
(`GET /api/v1/devices/{id}/files/download`), and it waits for the entire file before anything renders — so the app
feels slower than the website's streaming SignalR pipeline. Not a bug.

| Type | Rendered by | Notes |
|---|---|---|
| Images | the app, natively | ImageIO thumbnail decoding bounded to 2560 px — required, not an optimisation |
| PDF | the app, natively (PDFKit) | the whole document, scrollable |
| pptx / docx / xlsx / xls | a `WKWebView` on the server's `/preview/{token}` page | gets **only the short-lived token URL — never the API key**; `?theme=dark|light` is appended so the page follows the app's theme |
| Text | the app (editable) | UTF-8, Latin-1 fallback |

The file the preview pulled is kept in a one-entry cache (10-minute TTL, in-memory key) so Open, Save and the full
viewer reuse it; it is dropped whenever the app itself changes the file on the PC (a text save, an upload over the same
name) or on an explicit refresh.

## Console: destructive commands are confirmed first

`POST /api/v1/devices/{id}/exec` answers **409** `{ error, code: "confirm_destructive_required" }` for `del`, `rm`,
`Remove-Item`, `Move-Item`, `format`, `diskpart`, `Stop-Process`, `shutdown` and the like unless the body carries
`confirmDestructive: true`. The app turns that into a dialog quoting the exact command; **Yes** re-sends it with the
flag, **No** leaves the server's refusal in the history. The flag is never sent on a first attempt.

## Sign-in backends

"Sign in with Folderbird" uses `/app/authorize` + `/app/token` with `redirect_uri=folderbird://auth`, `client: "ios"`,
a `device_name` and a stable per-install `install_id` (so a re-sign-in retires this install's previous key only).
Sign-out POSTs `/app/revoke`. These endpoints are live on folderbird.com. A self-hosted server without them can use
the API-key option instead: create a key on the website under your account name → **Manage API keys**
(`/Manage/ApiKeys`) and paste it into the app's sign-in screen.

## Tech

Swift 5 · SwiftUI · `URLSession` · `AuthenticationServices` · `PDFKit` · `WebKit` · `QuickLook` · iOS / iPadOS 17+.
No third-party dependencies.

## Known gaps / roadmap

- [ ] HTTPS Universal-Link callback (`https://folderbird.com/app/callback`) — needs an Apple App Site Association
      file on the server; the custom scheme works today and is what the server allowlists for the mobile apps.
- [ ] Server-side thumbnails (a web-side feature) would be the real fix for large-image latency.
- [ ] Phase 2 (as on Android): device-as-agent.

## Privacy manifests

`Folderbird/Resources/PrivacyInfo.xcprivacy` and `ShareExtension/PrivacyInfo.xcprivacy` declare the two required-reason
API categories the code uses — the App Group's `UserDefaults` (reasons `1C8F.1` for the app-group suite the share extension shares, plus `CA92.1` for the `.standard` fallback) and file timestamps for the preview
cache sweep (`C617.1`). App Store Connect rejects an upload without them (ITMS-91053); CI checks that both bundles carry
one. If you add a required-reason API (disk space, system boot time, keyboard list, …), add its category and reason.
