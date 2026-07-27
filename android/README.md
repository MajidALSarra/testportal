# Brawl Legends — Android app

A thin native wrapper that runs the Brawl Legends web game (in [`../www`](../www))
inside a full-screen Android WebView. Building it produces a real, installable
`.apk`.

## What's here

```
android/
├── app/
│   ├── build.gradle                 app module config (SDK levels, assets)
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/brawllegends/game/MainActivity.java   full-screen WebView host
│       └── res/                     launcher icons, theme, strings
├── build.gradle                     Android Gradle Plugin version
├── settings.gradle
├── gradle.properties
└── gradlew / gradlew.bat            Gradle wrapper (Gradle 8.9)
```

The web game is **not** copied in — `app/build.gradle` adds `../../www` as an
assets source directory, so the same files that run on the web are bundled into
the APK and loaded from `file:///android_asset/index.html`.

## Build it

You need the Android SDK. The easiest path is **Android Studio**, which bundles
the SDK and all build tools.

### Option A — Android Studio (recommended)

1. Open Android Studio → **Open** → select this `android/` folder.
2. Let it sync Gradle (it downloads the Android Gradle Plugin and SDK bits the
   first time).
3. **Run ▶** on a connected phone or emulator, or **Build → Build APK(s)** to
   get an installable file.

### Option B — command line

With the Android SDK installed and `ANDROID_HOME` (or a `local.properties` with
`sdk.dir=/path/to/Android/sdk`) set:

```bash
cd android
./gradlew assembleDebug
```

The APK lands at:

```
app/build/outputs/apk/debug/app-debug.apk
```

Copy that to your phone and open it to install (you'll need to allow
"install from unknown sources" for your file manager or browser).

> This APK is signed with the auto-generated debug key — fine for playing it
> yourself and sideloading. To publish on the Play Store, add a real
> `signingConfig` and build `assembleRelease`.

## Why isn't a prebuilt APK included?

The APK has to be compiled with the Android SDK + Android Gradle Plugin, which
are downloaded from Google's servers. This project was authored in a sandbox
whose network policy blocks `dl.google.com`, so the build can't run there — but
it runs cleanly on any normal machine with Android Studio.

## Change the game

Edit the files in [`../www`](../www) (`index.html`, `style.css`, `game.js`) and
rebuild — the WebView picks them up as app assets automatically.
