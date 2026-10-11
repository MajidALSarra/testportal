#!/usr/bin/env bash
# Generates Folderbird.xcodeproj from project.yml (XcodeGen) and opens it. Run on a Mac with Xcode 15+.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "==> installing XcodeGen (brew)"
        brew install xcodegen
    else
        echo "XcodeGen is required: brew install xcodegen  (or see https://github.com/yonaskolb/XcodeGen)" >&2
        exit 1
    fi
fi

echo "==> xcodegen generate"
xcodegen generate

if [ "${1:-}" != "--no-open" ]; then
    open Folderbird.xcodeproj
fi

cat <<'MSG'

Next, in Xcode:
  1. Select the Folderbird target → Signing & Capabilities → pick your Team (do the same for FolderbirdShare).
     The App Group (group.com.folderbird.companion) and Keychain Sharing capabilities are already declared.
  2. Run on an iPhone / iPad or the Simulator (⌘R).
MSG
