# Releasing Glow

Release packages target **Apple Silicon arm64**, with macOS 14 as the minimum deployment target. Version 0.1.0 is a beta. Development tests ran on macOS 26.6.2; physical logo effects remain unverified on compatible hardware.

The CI workflow builds the app and runs focus-accounting checks. It does not sign, notarize, publish or exercise physical lighting.

## Prepare

```sh
swift run GlowChecks
./script/build_and_run.sh --verify
./script/release.sh --package
```

The release script builds optimized arm64 code, removes debug/local symbols, stages `dist/release/Glow.app`, includes licenses and the icon, and signs with Developer ID, a secure timestamp and the hardened runtime. It checks architecture, dynamic dependencies and the signature. The local debug app is preserved.

Output:

- `dist/release/Glow.app`
- `dist/release/Glow-0.1.0-arm64.zip`
- `dist/release/Glow-0.1.0-arm64.dmg`
- `dist/release/SHA256SUMS`
- `dist/release/RELEASE-STATUS.txt`

`--package` alone produces signed packages; it does not notarize them. Signing credentials remain in the local Keychain. To use another signing identity, set `GLOW_SIGN_IDENTITY` and `GLOW_TEAM_ID`. Version overrides use `GLOW_RELEASE_VERSION` and `GLOW_RELEASE_BUILD`.

## Notarize through Xcode

With full Xcode installed and its existing developer account signed in:

```sh
./script/notarize_xcode.sh --submit
```

The script creates a local archive, uploads it through Xcode, and exports the notarized app when ready. If processing is pending, inspect `build/notarization/export.log` and resume the same submission:

```sh
./script/notarize_xcode.sh --resume
./script/release.sh --package-stapled
```

If Apple rejects the upload because a developer-account agreement is missing or expired, accept that agreement in the account first. Inspect `build/notarization/upload.log` to distinguish a rejected upload from a pending submission. The upload marker prevents duplicate submissions; a confirmed rejected attempt needs a fresh submission after the account issue is resolved.

Do not rebuild or re-sign the validated exported app. `--package-stapled` recreates the ZIP with the app's notarization ticket intact and refreshes checksums.

The Xcode route notarizes and staples **the app**. The subsequently generated DMG is signed and contains that stapled app, but the DMG container itself has no separate notarization ticket. Use the ZIP as the primary download and describe the DMG accurately if publishing it.

## Alternative: notarytool profile

An existing Keychain profile can notarize and staple both the app and DMG:

```sh
NOTARY_PROFILE=your-profile ./script/release.sh --notarize
```

If the app was already exported and stapled through Xcode, this mode processes only the regenerated DMG:

```sh
NOTARY_PROFILE=your-profile ./script/release.sh --notarize-dmg
```

## Validate and publish

```sh
xcrun stapler validate dist/release/Glow.app
codesign --verify --strict --verbose=2 dist/release/Glow.app
spctl --assess --type execute --verbose=2 dist/release/Glow.app
cd dist/release
shasum -a 256 -c SHA256SUMS
```

Extract the final ZIP and repeat the signature/ticket checks on the extracted app. Confirm that the dashboard launches and that physical control remains off until enabled.

Update the notarization status in `README.md` and `docs/release-notes-0.1.0.md` only after validation. Publish tag `v0.1.0` as a GitHub prerelease on `Blacklord100/glow`, using those release notes. Attach the ZIP and `SHA256SUMS`; the DMG is optional. Keep Keychain data, account details, build caches and notarization logs out of the repository and release attachments.
