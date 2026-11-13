#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Glow"
BUNDLE_ID="app.glow.desktop"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"

case "$MODE" in
  run|--build-only|build-only|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"

# Restrict shutdown to the app built by this checkout, not another app named Glow.
running_pids=()
while IFS= read -r candidate_pid; do
  [[ -n "$candidate_pid" ]] || continue
  process_path="$(/bin/ps -p "$candidate_pid" -o comm= 2>/dev/null || true)"
  if [[ "$process_path" == "$APP_BINARY" ]]; then
    running_pids+=("$candidate_pid")
  fi
done < <(/usr/bin/pgrep -x "$APP_NAME" || true)

if (( ${#running_pids[@]} > 0 )); then
  # Normal application termination lets Glow restore any owned lighting state.
  /usr/bin/osascript -e 'with timeout of 3 seconds' \
    -e "tell application id \"$BUNDLE_ID\" to quit" \
    -e 'end timeout' >/dev/null 2>&1 || true
  for candidate_pid in "${running_pids[@]}"; do
    for _ in {1..20}; do
      /bin/kill -0 "$candidate_pid" 2>/dev/null || break
      /bin/sleep 0.1
    done
    if /bin/kill -0 "$candidate_pid" 2>/dev/null; then
      /bin/kill -TERM "$candidate_pid"
      for _ in {1..20}; do
        /bin/kill -0 "$candidate_pid" 2>/dev/null || break
        /bin/sleep 0.1
      done
      if /bin/kill -0 "$candidate_pid" 2>/dev/null; then
        echo "Glow did not exit. Quit it before rebuilding so lighting can be restored." >&2
        exit 1
      fi
    fi
  done
fi

/usr/bin/xcrun swift build --product "$APP_NAME"
BUILD_BINARY="$(/usr/bin/xcrun swift build --show-bin-path)/$APP_NAME"

if [[ ! -f "$ROOT_DIR/Resources/Glow.icns" || "$ROOT_DIR/script/make_icon.swift" -nt "$ROOT_DIR/Resources/Glow.icns" ]]; then
  /usr/bin/xcrun swift "$ROOT_DIR/script/make_icon.swift" "$ROOT_DIR/Resources/Glow.icns"
fi

# APP_BUNDLE is a fixed project-owned output path.
/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
/bin/cp "$BUILD_BINARY" "$APP_BINARY"
/bin/chmod +x "$APP_BINARY"
/bin/cp "$ROOT_DIR/Resources/Glow.icns" "$APP_CONTENTS/Resources/Glow.icns"
if [[ -d "$ROOT_DIR/ThirdParty" ]]; then
  /bin/cp -R "$ROOT_DIR/ThirdParty" "$APP_CONTENTS/Resources/ThirdParty"
fi

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>Glow</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$APP_CONTENTS/Info.plist" >/dev/null
/usr/bin/codesign --force --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-only|build-only)
    echo "Built $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/xcrun lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'process == "Glow"'
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.glow.desktop"'
    ;;
  --verify|verify)
    open_app
    /bin/sleep 1
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null
    echo "Glow is running: $APP_BUNDLE"
    ;;
esac
