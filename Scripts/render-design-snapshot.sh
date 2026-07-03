#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/design-tools"
OUTPUT_PATH="${1:-$ROOT_DIR/.build/design-snapshot.png}"
COLOR_SCHEME="${2:-light}"
SCENARIO="${3:-ready}"
WIDTH="${4:-1280}"
HEIGHT="${5:-800}"
SWIFTC="${SWIFTC:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc}"
SDKROOT="${SDKROOT:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/voice-to-markdown-clang-cache}"
export CLANG_MODULE_CACHE_PATH

mkdir -p "$BUILD_DIR"

sources=()
for file in "$ROOT_DIR"/Sources/VoiceToMarkdown/*.swift; do
  case "$(basename "$file")" in
    VoiceToMarkdownApp.swift)
      ;;
    *)
      sources+=("$file")
      ;;
  esac
done

"$SWIFTC" \
  -sdk "$SDKROOT" \
  -target arm64-apple-macosx14.0 \
  "${sources[@]}" \
  "$ROOT_DIR/Tools/RenderDesignSnapshot.swift" \
  -o "$BUILD_DIR/render-design-snapshot" \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework Speech

"$BUILD_DIR/render-design-snapshot" "$OUTPUT_PATH" "$COLOR_SCHEME" "$SCENARIO" "$WIDTH" "$HEIGHT"
