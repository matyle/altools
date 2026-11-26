#!/usr/bin/env bash
# Builds Altools.app into ./build. Usage: scripts/build-app.sh [debug|release] [install|dmg]
# "install" also copies it to /Applications, the copy to run: macOS 27 refuses menu bar
# items from the ./build location. "dmg" also makes build/Altools.dmg, a disk image with
# the app beside an Applications shortcut to drag it onto.
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
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
# The plugin guide (read by the AI plugin maker) and the example plugins (Settings › Install examples).
cp "$root/PLUGINS.md" "$app/Contents/Resources/PLUGINS.md"
cp -R "$root/examples/plugins" "$app/Contents/Resources/PluginExamples"
cp -R "$root/Resources/BuiltinPlugins" "$app/Contents/Resources/BuiltinPlugins"
cp "$root/plugins/registry.json" "$app/Contents/Resources/registry.json"

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
codesign --force --sign "$identity" --identifier local.altools.menubar "$app"

echo "Built $app (signed with: $identity)"

if [[ "${2:-}" == "install" ]]; then
  rm -rf /Applications/Altools.app
  cp -R "$app" /Applications/Altools.app
  echo "Installed /Applications/Altools.app"
fi

if [[ "${2:-}" == "dmg" ]]; then
  rm -f "$root/build/Altools.dmg"
  if command -v dmgbuild >/dev/null 2>&1; then
    # Window layout and background need dmgbuild (pip install dmgbuild); it works without Finder.
    dmgbuild -s "$root/scripts/dmg-settings.py" -D app="$app" -D background="$root/Resources/dmg-background.png" \
      "Altools" "$root/build/Altools.dmg"
  else
    staging="$root/build/dmg"
    rm -rf "$staging"
    mkdir -p "$staging"
    cp -R "$app" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -quiet -volname "Altools" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$root/build/Altools.dmg"
    rm -rf "$staging"
  fi
  echo "Built $root/build/Altools.dmg"
fi
