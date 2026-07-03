#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/.build/Voice to Markdown.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SWIFTC="${SWIFTC:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc}"
SDKROOT="${SDKROOT:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/voice-to-markdown-clang-cache}"
export CLANG_MODULE_CACHE_PATH

mkdir -p "$BUILD_DIR"
"$SWIFTC" \
  -sdk "$SDKROOT" \
  -target arm64-apple-macosx14.0 \
  "$ROOT_DIR"/Sources/VoiceToMarkdown/*.swift \
  -o "$BUILD_DIR/VoiceToMarkdown" \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework Speech

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/VoiceToMarkdown" "$MACOS_DIR/VoiceToMarkdown"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --entitlements "$ROOT_DIR/Packaging/VoiceToMarkdown.entitlements" "$APP_DIR"
fi

echo "$APP_DIR"
