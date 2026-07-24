# Countdown — Android app + home-screen widgets

Create as many countdowns as you like, each drawn in its own **animated style**,
and put any of them on your home screen as a **widget** that uses the exact same
look.

## Features

- **Multiple countdowns** — a beautiful scrolling list; tap a card to edit,
  long-press to delete, tap **+** to add.
- **Five appearance styles**, each animated:
  - **Ring** — a depleting progress ring with a glowing head and the days in the centre
  - **Boxes** — Days / Hours / Minutes / Seconds tiles with a ticking seconds pulse
  - **Bars** — progress bars for each unit with a moving shimmer
  - **Triangles** — liquid-fill triangles with a rippling surface
  - **Dots** — a ring of dots that empties over time with an orbiting comet
- **Six colour themes** per countdown.
- **Home-screen widget** — renders the chosen countdown in the same style. When
  you drop a widget you pick which countdown it shows; it refreshes about once a
  minute and tapping it opens the app.

The app and the widget share one `Canvas` renderer, so a countdown looks
identical in both places. (Animation runs live in the app; the widget shows a
crisp still frame that updates each minute — Android widgets can't animate
continuously.)

## Install the APK

1. Copy `build/Countdown.apk` to your phone.
2. Open it and allow "install from unknown sources" if prompted.
3. Open **Countdown**, tap **+**, set a title + days/hours/minutes, pick a style
   and colour, **Save**.
4. Add a widget: long-press the home screen → **Widgets** → **Countdown** →
   drop it, then choose which countdown it should show.

Requires **Android 7.0 (API 24) or newer**. Signed with an APK Signature
Scheme v2 signature.

## Building it yourself

No Android Studio / Android SDK needed — `build_apk.sh` fetches a minimal
toolchain from Maven Central plus a public `android.jar` mirror, then compiles,
dexes and signs by hand:

```bash
./build_apk.sh      # -> build/Countdown.apk
```

| Piece | Source |
|-------|--------|
| `aapt2` (resource compiler) | bundled inside `org.apktool:apktool-lib` |
| `android.jar` (API 34 stub) | `Sable/android-platforms` mirror |
| `dalvik-dx` (dexer)         | `com.jakewharton.android.repackaged:dalvik-dx` |
| `apksig` (v2 signer)        | `com.android.tools.build:apksig` |

Downloaded tools are cached in `.buildtools/` (git-ignored); the build key is
generated on first run.

## Project layout

```
app/
  AndroidManifest.xml
  java/com/majid/countdown/
    Countdown.java            # model
    Store.java                # JSON persistence + widget bindings
    CountdownRenderer.java    # the 5 styles, drawn on a Canvas (app + widget)
    CountdownView.java        # animated card view used in the app
    MainActivity.java         # the list
    EditActivity.java         # add/edit: title, time, style, colour
    CountdownWidget.java      # AppWidgetProvider (renders bitmaps)
    WidgetConfigActivity.java # pick which countdown a widget shows
  res/
    layout/widget_countdown.xml
    xml/countdown_widget_info.xml
    drawable/, values/
build_apk.sh                  # SDK-free build + sign pipeline
```
