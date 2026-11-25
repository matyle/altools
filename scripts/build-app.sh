#!/usr/bin/env bash
# Builds Altools.app into ./build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

config="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Altools.app"

cd "$root"
swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)/Altools"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Altools"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"

# System Now Playing bridge, loaded into /usr/bin/perl at runtime (see NowPlaying.swift).
mkdir -p "$app/Contents/Frameworks"
clang -dynamiclib -fobjc-arc -O2 -framework Foundation -framework AppKit \
  -o "$app/Contents/Frameworks/libAltoolsMedia.dylib" "$root/Bridge/MediaBridge.m"

# Signs with $ALTOOLS_SIGN_IDENTITY, else the local "Altools Dev" certificate if it
# exists, else ad-hoc. Ad-hoc changes identity on every build, so macOS forgets
# Accessibility / Screen Recording grants after each rebuild; a fixed certificate keeps them.
default_identity="-"
if security find-identity -p codesigning 2>/dev/null | grep -q '"Altools Dev"'; then
  default_identity="Altools Dev"
fi
identity="${ALTOOLS_SIGN_IDENTITY:-$default_identity}"
codesign --force --sign "$identity" "$app/Contents/Frameworks/libAltoolsMedia.dylib"
codesign --force --sign "$identity" --identifier local.altools.app "$app"

echo "Built $app (signed with: $identity)"
