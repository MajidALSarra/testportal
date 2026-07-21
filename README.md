# Countdown — Android app + home-screen widget

A tiny Android app that lets you set a countdown in **days, hours and minutes**
and shows the time remaining in a **home-screen widget**.

![icon](app/res/drawable/ic_launcher.xml)

## What it does

- **App screen** — enter a title plus days / hours / minutes, tap **Start
  countdown**. The target time is saved and the widget updates immediately.
  On Android 8+ it also asks your launcher to pin the widget for you.
- **Home-screen widget** — shows the big number of **days** left, plus
  `Hh Mm left` underneath, and the countdown title. It refreshes about once a
  minute and again whenever Android asks it to. Tapping it opens the app.
  When the target passes it shows **Finished!**

## Install the APK

1. Copy `build/Countdown.apk` to your phone.
2. Open it and allow "install from unknown sources" if prompted.
3. Open **Countdown**, set your time, tap **Start countdown**.
4. Add the widget: long-press an empty spot on the home screen →
   **Widgets** → **Countdown** → drag it out.

Requires **Android 7.0 (API 24) or newer**. The APK is signed with an APK
Signature Scheme v2 signature.

## Building it yourself

There is no Android Studio / Android SDK dependency. `build_apk.sh` pulls a
minimal toolchain from Maven Central and a public `android.jar` mirror, then
compiles, dexes and signs the APK by hand:

```bash
./build_apk.sh
# -> build/Countdown.apk
```

| Piece | Source |
|-------|--------|
| `aapt2` (resource compiler) | bundled inside `org.apktool:apktool-lib` |
| `android.jar` (API 34 stub) | `Sable/android-platforms` mirror |
| `dalvik-dx` (dexer)         | `com.jakewharton.android.repackaged:dalvik-dx` |
| `apksig` (v2 signer)        | `com.android.tools.build:apksig` |

Downloaded tools are cached in `.buildtools/` (git-ignored) and the build key
is generated on first run.

## Project layout

```
app/
  AndroidManifest.xml
  java/com/majid/countdown/
    MainActivity.java        # set title + days/hours/minutes
    CountdownWidget.java      # AppWidgetProvider: renders + auto-refreshes
  res/
    layout/activity_main.xml
    layout/widget_countdown.xml
    xml/countdown_widget_info.xml
    drawable/, values/
build_apk.sh                  # SDK-free build + sign pipeline
```
