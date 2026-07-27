# 🦅 Brawl Legends

A **Brawl Stars–style** top-down arena brawler, built with HTML5 Canvas + vanilla
JavaScript. No frameworks. Runs in a browser, installs as a web app, and ships
as a native **Android** app.

## The Brawlers

| Brawler | Animal | Role | Play style |
|---------|--------|------|------------|
| **Sagoory** | 🦅 Eagle | Sharpshooter | Fast and fragile. Rains rapid feather-darts from long range. **SUPER — Talon Dive:** launches forward through enemies, firing a fan of feathers. |
| **Hadoosh** | 🦏 Goofy two-legged rhino | Tank | Huge health, close-range shotgun spread. **SUPER — Rhino Charge:** an unstoppable charge that flattens and knocks back everything it hits. |
| **Saeedan** | 🐑 Sheep | Support | Balanced fighter that lobs wool bombs. **SUPER — Wool Bloom:** heals itself and bursts nearby enemies with a cloud of fleece. |

## How to Play

- **Move** — `W` `A` `S` `D` / arrow keys, or **drag the left half** of the screen on touch
- **Aim & Shoot** — mouse + hold **left click**, or **drag the right half** on touch
- **SUPER** — `Space` / `Q` when charged, or tap the **SUPER** button
- **Pause** — `P` / `Esc` / the ⏸ button

Hide in **bushes** 🌳 to go invisible, smash **crates** 📦 for heal / super
power-ups, and survive escalating waves. Every takedown scores 100 points and
charges your SUPER.

## Play it

**Web** — open the single-file build directly, no server needed:

```
# just double-click, or:
xdg-open index.html      # Linux
open index.html          # macOS
start index.html         # Windows
```

`index.html` is fully self-contained (CSS + JS inlined), so it works even when
opened from a phone file manager.

**Install as an app (web)** — serve the `www/` folder over HTTPS and use your
browser's *Add to Home Screen* / *Install app*. It's a PWA (manifest + offline
service worker) and launches full-screen with its own icon.

**Android** — build the native app in [`android/`](android/):

```
cd android
./gradlew assembleDebug        # needs the Android SDK (Android Studio bundles it)
# -> app/build/outputs/apk/debug/app-debug.apk
```

See [`android/README.md`](android/README.md) for the full walkthrough. (A
prebuilt APK isn't committed because compiling it requires Google's SDK servers,
which the authoring sandbox couldn't reach — it builds cleanly in Android Studio.)

## Project layout

```
index.html      self-contained single-file build (generated — open this to play)
build.js        inlines www/ into index.html
www/            web app source (edit here)
  index.html    screens: menu, how-to-play, game, game-over
  style.css     UI styling + animated SUPER ring
  game.js       engine: brawler art, physics, AI, waves, input, rendering
  manifest.webmanifest, sw.js   PWA install + offline
  icons/        app icons (Sagoory)
android/        native Android WebView wrapper (build -> APK)
```

After editing anything in `www/`, regenerate the single-file build:

```
node build.js
```

All character art — the eagle, rhino, and sheep — is drawn procedurally with
Canvas primitives. No image assets required (the app icons are the only PNGs).
