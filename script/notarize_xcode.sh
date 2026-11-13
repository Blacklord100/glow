#!/usr/bin/env bash
set -euo pipefail

# Uses the existing account in Xcode; does not extract or create credentials.
# Build/sign with release.sh --package first. Pending submissions are resumed,
# never silently rebuilt or uploaded twice.
MODE="${1:---submit}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
GLOW_TEAM_ID="${GLOW_TEAM_ID:-78UF8SJT35}"
WORK_DIR="$ROOT_DIR/build/notarization"
ARCHIVE="$WORK_DIR/Glow.xcarchive"
APP="$ROOT_DIR/dist/release/Glow.app"
MARKER="$WORK_DIR/upload-attempted"

case "$MODE" in --submit|--resume) ;; *) echo "Usage: $0 [--submit|--resume]" >&2; exit 2 ;; esac
[[ -d "$DEVELOPER_DIR" ]] || { echo "A full Xcode installation with a signed-in developer account is required." >&2; exit 2; }
mkdir -p "$WORK_DIR"

if [[ "$MODE" == "--submit" ]]; then
  [[ -d "$APP" ]] || { echo "Run script/release.sh --package first." >&2; exit 2; }
  [[ ! -f "$MARKER" ]] || { echo "An upload was already attempted. Inspect its log and use --resume." >&2; exit 75; }
  codesign --verify --strict "$APP"
  mkdir -p "$ARCHIVE/Products/Applications"
  ditto "$APP" "$ARCHIVE/Products/Applications/Glow.app"
  python3 - "$ARCHIVE" "$GLOW_TEAM_ID" "$WORK_DIR/ExportOptions.plist" <<'PY'
import datetime, pathlib, plistlib, sys
archive, team, options = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
info = plistlib.loads((archive / 'Products/Applications/Glow.app/Contents/Info.plist').read_bytes())
properties = {
    'ApplicationPath': 'Applications/Glow.app',
    'CFBundleIdentifier': info['CFBundleIdentifier'],
    'CFBundleShortVersionString': info['CFBundleShortVersionString'],
    'CFBundleVersion': info['CFBundleVersion'],
    'SigningIdentity': 'Developer ID Application',
    'Team': team,
}
(archive / 'Info.plist').write_bytes(plistlib.dumps({
    'ArchiveVersion': 2, 'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    'Name': 'Glow', 'SchemeName': 'Glow', 'ApplicationProperties': properties,
}))
options.write_bytes(plistlib.dumps({
    'method': 'developer-id', 'destination': 'upload', 'teamID': team,
    'signingStyle': 'automatic',
}))
PY
  touch "$MARKER"
  UPLOAD_DIR="$(mktemp -d "$WORK_DIR/upload.XXXXXX")"
  echo "Submitting Glow through the existing Xcode account. Log: $WORK_DIR/upload.log"
  if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$UPLOAD_DIR" \
       -exportOptionsPlist "$WORK_DIR/ExportOptions.plist" -allowProvisioningUpdates \
       > "$WORK_DIR/upload.log" 2>&1; then
    echo "Upload did not finish successfully. Inspect $WORK_DIR/upload.log before retrying." >&2
    exit 1
  fi
fi

[[ -d "$ARCHIVE" ]] || { echo "No archive to resume." >&2; exit 2; }
EXPORT_DIR="$(mktemp -d "$WORK_DIR/export.XXXXXX")"
echo "Checking Apple's notarization result. Log: $WORK_DIR/export.log"
if ! xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
     -allowProvisioningUpdates > "$WORK_DIR/export.log" 2>&1; then
  echo "Notarized export is not ready. Inspect $WORK_DIR/export.log, then run --resume." >&2
  exit 75
fi
xcrun stapler validate "$EXPORT_DIR/Glow.app"
codesign --verify --strict "$EXPORT_DIR/Glow.app"
spctl --assess --type execute --verbose=2 "$EXPORT_DIR/Glow.app"

# Preserve the validated exported signature/ticket exactly; no re-signing.
rm -rf "$APP"
ditto "$EXPORT_DIR/Glow.app" "$APP"
echo "Notarized app ready at $APP"
echo "Run script/release.sh --package-stapled to recreate the download archives."
