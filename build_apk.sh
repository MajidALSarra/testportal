#!/usr/bin/env bash
# Builds and signs the Countdown APK WITHOUT the full Android SDK (which needs
# dl.google.com). Every tool is pulled from Maven Central / a public mirror:
#   - aapt2        extracted from apktool-lib      (Maven Central)
#   - android.jar  Android 34 stub                 (Sable/android-platforms mirror)
#   - dalvik-dx    modern standalone dexer         (Maven Central)
#   - apksig       Google APK signing library      (Maven Central)
# Downloaded artifacts are cached under .buildtools/ (git-ignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BT="$ROOT/.buildtools"
APP="$ROOT/app"
OUT="$ROOT/build"
PKG="com.majid.countdown"

AAPT2="$BT/aapt2"
ANDROID_JAR="$BT/android.jar"
DX="$BT/dalvik-dx.jar"
APKSIG="$BT/apksig.jar"
KS="$BT/countdown.keystore"

MIN_SDK=24
TARGET_SDK=34

MC="https://repo1.maven.org/maven2"
mkdir -p "$BT"

fetch() { # url dest
    if [ ! -f "$2" ]; then echo "    downloading $(basename "$2")"; curl -fsSL --retry 3 -o "$2" "$1"; fi
}

echo "==> [0/7] bootstrap toolchain"
fetch "$MC/com/jakewharton/android/repackaged/dalvik-dx/16.0.1/dalvik-dx-16.0.1.jar" "$DX"
fetch "$MC/com/android/tools/build/apksig/2.3.0/apksig-2.3.0.jar" "$APKSIG"
fetch "https://raw.githubusercontent.com/Sable/android-platforms/master/android-34/android.jar" "$ANDROID_JAR"
if [ ! -x "$AAPT2" ]; then
    fetch "$MC/org/apktool/apktool-lib/3.0.3/apktool-lib-3.0.3.jar" "$BT/apktool-lib.jar"
    ( cd "$BT" && unzip -o -q apktool-lib.jar prebuilt/linux/aapt2 && cp prebuilt/linux/aapt2 aapt2 && chmod +x aapt2 )
fi

rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/obj"

echo "==> [1/7] aapt2 compile resources"
"$AAPT2" compile --dir "$APP/res" -o "$OUT/res.zip"

echo "==> [2/7] aapt2 link (binary manifest + resources.arsc + R.java)"
"$AAPT2" link \
    -o "$OUT/base.apk" \
    -I "$ANDROID_JAR" \
    --manifest "$APP/AndroidManifest.xml" \
    -R "$OUT/res.zip" \
    --java "$OUT/gen" \
    --min-sdk-version "$MIN_SDK" \
    --target-sdk-version "$TARGET_SDK" \
    --version-code 1 \
    --version-name "1.0" \
    --auto-add-overlay

echo "==> [3/7] javac (Java 8 bytecode for the dexer)"
find "$OUT/gen" "$APP/java" -name '*.java' > "$OUT/sources.txt"
javac -source 8 -target 8 -encoding UTF-8 -nowarn \
    -bootclasspath "$ANDROID_JAR" \
    -classpath "$ANDROID_JAR" \
    -d "$OUT/obj" \
    @"$OUT/sources.txt" 2>/dev/null

echo "==> [4/7] dx -> classes.dex"
java -cp "$DX" com.android.dx.command.Main --dex \
    --output="$OUT/classes.dex" "$OUT/obj"

echo "==> [5/7] package classes.dex into the APK"
cp "$OUT/base.apk" "$OUT/unsigned.apk"
( cd "$OUT" && zip -q unsigned.apk classes.dex )

echo "==> [6/7] sign (APK Signature Scheme v2)"
if [ ! -f "$KS" ]; then
    echo "    generating signing key"
    keytool -genkeypair -keystore "$KS" -storetype PKCS12 \
        -storepass countdown -keypass countdown -alias countdown \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Countdown, O=Countdown, C=US" >/dev/null 2>&1
fi
javac -classpath "$APKSIG" -d "$BT" "$BT/ApkSignerTool.java"
java \
    --add-exports java.base/sun.security.x509=ALL-UNNAMED \
    --add-exports java.base/sun.security.pkcs=ALL-UNNAMED \
    -cp "$APKSIG:$BT" ApkSignerTool \
    "$KS" countdown countdown "$MIN_SDK" \
    "$OUT/unsigned.apk" "$OUT/Countdown.apk"

echo "==> [7/7] verify signatures"
javac -classpath "$APKSIG" -d "$BT" "$BT/ApkVerifierTool.java"
java --add-exports java.base/sun.security.x509=ALL-UNNAMED \
    -cp "$APKSIG:$BT" ApkVerifierTool "$OUT/Countdown.apk"

echo
echo "==> DONE: $OUT/Countdown.apk"
ls -la "$OUT/Countdown.apk"
