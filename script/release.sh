#!/usr/bin/env bash
set -euo pipefail

# Run this script from any directory. It never stops or replaces the local debug app.
#   ./script/release.sh --package
#   NOTARY_PROFILE=glow-notary ./script/release.sh --notarize
#   ./script/release.sh --package-stapled  # after an external notarized app export
#   NOTARY_PROFILE=glow-notary ./script/release.sh --notarize-dmg

MODE="${1:---package}"
GLOW_RELEASE_VERSION="${GLOW_RELEASE_VERSION:-0.1.0}"
GLOW_RELEASE_BUILD="${GLOW_RELEASE_BUILD:-1}"
GLOW_SIGN_IDENTITY="${GLOW_SIGN_IDENTITY:-F1C8D7296EB73768BFFC71790E42C18D3CC55AEB}"
GLOW_TEAM_ID="${GLOW_TEAM_ID:-78UF8SJT35}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/Glow.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Glow"
STEM="Glow-$GLOW_RELEASE_VERSION-arm64"
ZIP_PATH="$RELEASE_DIR/$STEM.zip"
DMG_PATH="$RELEASE_DIR/$STEM.dmg"
DMG_STAGE=""

die() { echo "Release error: $*" >&2; exit 1; }

case "$MODE" in
  --package|--notarize|--package-stapled|--notarize-dmg) ;;
  *) die "usage: $0 [--package|--notarize|--package-stapled|--notarize-dmg]" ;;
esac
[[ "$GLOW_RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "GLOW_RELEASE_VERSION must be a three-part numeric version."
[[ "$GLOW_RELEASE_BUILD" =~ ^[1-9][0-9]*$ ]] || die "GLOW_RELEASE_BUILD must be a positive integer."

cleanup() {
  if [[ -n "$DMG_STAGE" && -d "$DMG_STAGE" ]]; then /bin/rm -rf "$DMG_STAGE"; fi
}
trap cleanup EXIT
/bin/mkdir -p "$RELEASE_DIR"
cd "$ROOT_DIR"

verify_binary() {
  [[ -f "$APP_BINARY" ]] || die "Missing $APP_BINARY; run --package first."
  local arch
  arch="$(/usr/bin/lipo -archs "$APP_BINARY")"
  [[ "$arch" == "arm64" ]] || die "Expected an Apple Silicon arm64 binary, found: $arch"
  /usr/bin/otool -L "$APP_BINARY" | /usr/bin/sed '1d' > "$RELEASE_DIR/dependencies.txt"
  local line dependency
  while IFS= read -r line; do
    dependency="${line%% (*}"
    dependency="${dependency#"${dependency%%[![:space:]]*}"}"
    case "$dependency" in
      /System/Library/*|/usr/lib/*|@rpath/libswift*.dylib) ;;
      *) die "Unbundled or unexpected dynamic dependency: $dependency" ;;
    esac
  done < "$RELEASE_DIR/dependencies.txt"
}

verify_app() {
  verify_binary
  /usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null
  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_BUNDLE/Contents/Info.plist")" == "app.glow.desktop" ]] || die "Unexpected app bundle identifier."
  [[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP_BUNDLE/Contents/Info.plist")" == "$GLOW_RELEASE_VERSION" ]] || die "App version does not match release version."
  /usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE"
  local signing
  signing="$(/usr/bin/codesign -dvv "$APP_BUNDLE" 2>&1)"
  [[ "$signing" == *"TeamIdentifier=$GLOW_TEAM_ID"* ]] || die "App is not signed by the expected Developer ID team."
  [[ "$signing" == *"Authority=Developer ID Application:"* ]] || die "App lacks a Developer ID Application signature."
  [[ "$signing" == *"(runtime)"* ]] || die "App signature does not enable the hardened runtime."
  [[ "$signing" == *"Timestamp="* ]] || die "App signature lacks a secure signing timestamp."
}

make_zip() {
  /bin/rm -f "$ZIP_PATH"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
}

make_dmg() {
  DMG_STAGE="$(/usr/bin/mktemp -d "$RELEASE_DIR/.dmg-stage.XXXXXX")"
  /usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGE/Glow.app"
  /bin/ln -s /Applications "$DMG_STAGE/Applications"
  cat > "$DMG_STAGE/Install Glow.txt" <<'INSTALL'
Glow for Apple Silicon

1. Drag Glow.app to Applications.
2. Open Glow from Applications.
3. Use the Glow item in your menu bar to open the dashboard or start a focus session.

Requires macOS 14 or later and an Apple Silicon Mac.

Focus tracking and on-screen light previews work without an illuminated logo.
Physical lighting needs a detected compatible PROLED MacBook controller and is
experimental. Enable it explicitly in Lights. Individual LED and physical height
control remain unverified; Logo Lab's filling Apple is an on-screen simulation.

Quit Glow from its menu-bar panel before replacing or removing the app.
INSTALL
  /usr/bin/hdiutil create -volname "Glow $GLOW_RELEASE_VERSION" -srcfolder "$DMG_STAGE" \
    -format UDZO -imagekey zlib-level=9 -fs HFS+ -ov "$DMG_PATH"
  /bin/rm -rf "$DMG_STAGE"
  DMG_STAGE=""
  /usr/bin/codesign --force --sign "$GLOW_SIGN_IDENTITY" --timestamp "$DMG_PATH"
  /usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
}

write_checksums() {
  (cd "$RELEASE_DIR" && /usr/bin/shasum -a 256 "$STEM.zip" "$STEM.dmg") > "$RELEASE_DIR/SHA256SUMS"
}

write_status() {
  cat > "$RELEASE_DIR/RELEASE-STATUS.txt" <<STATUS
Glow $GLOW_RELEASE_VERSION (build $GLOW_RELEASE_BUILD)
Architecture: arm64 (Apple Silicon only)
Minimum macOS: 14.0
Developer ID team: $GLOW_TEAM_ID
$1
STATUS
}

require_profile() {
  [[ -n "${NOTARY_PROFILE:-}" ]] || die "Set NOTARY_PROFILE to an existing notarytool Keychain profile."
}

submit_notary() {
  local artifact="$1" label="$2" result="$RELEASE_DIR/notary-$2.json"
  require_profile
  echo "Submitting $(/usr/bin/basename "$artifact") to Apple notarization."
  if ! /usr/bin/xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" \
      --wait --timeout 20m --output-format json > "$result"; then
    die "Notarization did not finish successfully. Details: $result (submission may still be processing)."
  fi
  local status
  status="$(/usr/bin/plutil -extract status raw -o - "$result" 2>/dev/null || true)"
  [[ "$status" == "Accepted" ]] || die "Apple returned '$status' for $label. Details: $result"
}

staple_app() {
  /usr/bin/xcrun stapler staple "$APP_BUNDLE"
  /usr/bin/xcrun stapler validate "$APP_BUNDLE"
  verify_app
  /usr/sbin/spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
}

notarize_dmg() {
  [[ -f "$DMG_PATH" ]] || die "Missing DMG; run --package or --package-stapled first."
  submit_notary "$DMG_PATH" dmg
  /usr/bin/xcrun stapler staple "$DMG_PATH"
  /usr/bin/xcrun stapler validate "$DMG_PATH"
  /usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
}

case "$MODE" in
  --package)
    /usr/bin/xcrun swift build -c release --arch arm64 --product Glow \
      -Xswiftc -debug-prefix-map -Xswiftc "$ROOT_DIR=."
    BUILD_BINARY="$(/usr/bin/xcrun swift build -c release --arch arm64 --show-bin-path)/Glow"
    [[ -f "$ROOT_DIR/Resources/Glow.icns" ]] || die "App icon missing; run script/make_icon.swift first."
    /bin/rm -rf "$APP_BUNDLE"
    /bin/mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
    /bin/cp "$BUILD_BINARY" "$APP_BINARY"
    /bin/chmod +x "$APP_BINARY"
    /usr/bin/xcrun strip -S -x "$APP_BINARY"
    /bin/cp "$ROOT_DIR/Resources/Glow.icns" "$APP_BUNDLE/Contents/Resources/Glow.icns"
    if [[ -f "$ROOT_DIR/LICENSE" ]]; then
      /bin/cp "$ROOT_DIR/LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE.txt"
    fi
    if [[ -d "$ROOT_DIR/ThirdParty" ]]; then
      /bin/cp -R "$ROOT_DIR/ThirdParty" "$APP_BUNDLE/Contents/Resources/ThirdParty"
    fi
    cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Glow</string>
  <key>CFBundleIdentifier</key><string>app.glow.desktop</string>
  <key>CFBundleName</key><string>Glow</string>
  <key>CFBundleDisplayName</key><string>Glow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$GLOW_RELEASE_VERSION</string>
  <key>CFBundleVersion</key><string>$GLOW_RELEASE_BUILD</string>
  <key>CFBundleIconFile</key><string>Glow</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
    verify_binary
    /usr/bin/codesign --force --sign "$GLOW_SIGN_IDENTITY" --options runtime --timestamp "$APP_BUNDLE"
    verify_app
    make_zip
    make_dmg
    write_checksums
    write_status "App and DMG are Developer ID signed. Notarization has not been performed."
    echo "Signed packages created in $RELEASE_DIR. They are not yet notarized."
    ;;
  --notarize)
    require_profile
    verify_app
    make_zip
    submit_notary "$ZIP_PATH" app
    staple_app
    make_zip
    make_dmg
    notarize_dmg
    write_checksums
    write_status "App and DMG are notarized, stapled and validated. ZIP includes the stapled app."
    echo "Notarized release ready in $RELEASE_DIR."
    ;;
  --package-stapled)
    verify_app
    /usr/bin/xcrun stapler validate "$APP_BUNDLE"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
    make_zip
    make_dmg
    write_checksums
    write_status "App is notarized and stapled. ZIP includes its ticket. DMG is signed and contains the stapled app, but the DMG itself has not been notarized/stapled by this script."
    echo "Packaged the existing stapled app. Run --notarize-dmg to also staple the DMG."
    ;;
  --notarize-dmg)
    require_profile
    verify_app
    /usr/bin/xcrun stapler validate "$APP_BUNDLE"
    # Rebuild both containers from this exact stapled app, avoiding stale packages
    # if the caller replaced Glow.app with an external notarized export.
    make_zip
    make_dmg
    notarize_dmg
    write_checksums
    write_status "App and DMG are notarized, stapled and validated. ZIP includes the stapled app."
    ;;
esac
