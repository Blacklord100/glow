# Glow

A native Mac menu-bar app that turns focused time into a little more glow.

Start a focus session and watch your daily charge grow in the menu bar and dashboard. Take breaks, add offline work, and see your last seven days—all saved locally.

## Download

[Download Glow 0.1.0 beta for Apple Silicon](https://github.com/Blacklord100/glow/releases/download/v0.1.0/Glow-0.1.0-arm64.zip) · [Release notes](docs/release-notes-0.1.0.md)

**Developer ID signed and notarized by Apple.** The ZIP includes the app’s stapled notarization ticket.

Requires **macOS 14 or later and an Apple Silicon Mac**. Unzip the download, move `Glow.app` to Applications, and open it. Glow lives in the menu bar without a Dock icon; close the dashboard and reopen it from the menu-bar item.

## What it does

- **Daily Charge:** a growing on-screen Apple and menu-bar meter for your daily focus goal.
- **Focus sessions:** 25, 45 or 60 minutes, with pause, resume and manual additions for offline work.
- **Seven-day history:** a small view of your accumulated focused time.
- **Light previews:** Breathe, Pulse, Daily Charge, System Default and Off.
- **Logo Lab:** a height-fill simulation and read-only hardware report for investigating the physical logo.
- **Launch at login:** optional, in Settings.

## Physical Apple-logo control

The focus tracker and previews work without an illuminated logo. Physical effects require a compatible **MacBook Pro with PROLED XDR Display**, a detected controller, and explicit opt-in each launch. They use experimental private CoreBrightness interfaces and have **not yet been tested on compatible logo hardware**. macOS changes may affect support.

The implemented physical controls are whole-logo Breathe, Pulse and temporary Off. Daily Charge uses brief milestone pulses. Disabling physical control or quitting normally attempts to restore the previous logo state and normal fade timing. Unsupported hardware remains in labelled preview mode.

**Individual LED control and a physical rising fill are not implemented.** The filling Apple in the dashboard and Logo Lab is an on-screen simulation. Four visible LEDs do not establish whether separate software channels exist; the read-only scan helps investigate that question without changing unknown registers.

Development testing has been performed on macOS 26.6.2. The deployment target is macOS 14, but older versions and physical logo effects still need device testing.

## Privacy

Focus history and preferences stay on your Mac. Sessions are explicit; paused, sleeping and offline time is not automatically credited. Glow does not record your screen, keystrokes, apps or websites, and it has no tracking server.

## Build from source

Requires Swift 6 and Xcode or Apple's Command Line Tools.

```sh
./script/build_and_run.sh
```

This builds and launches an ad-hoc signed development app at `dist/Glow.app`. The Codex Run action uses the same script. Add `--build-only`, `--verify`, `--debug`, `--logs` or `--telemetry` when needed.

```sh
swift run GlowChecks   # focus accounting checks
swift run GlowInspect # read-only hardware diagnostics
```

The debug build also includes an isolated native-view and app-action harness:

```sh
open -n dist/Glow.app --args --render-previews "$PWD/dist/previews"
```

It writes preview images and `checks.txt`, uses sample data without changing saved history, and never enables physical lighting. These renders complement interactive and hardware testing.

Some Command Line Tools installations expose SwiftUI's newer `State` macro without its plugin. Glow's `@ViewState` alias uses the stable `SwiftUI.State` property wrapper; use the same alias when adding local view state if you encounter a missing `SwiftUIMacros` error.

See [release packaging](docs/RELEASE.md) for Developer ID signing and notarization.

## Credits and license

Glow is [MIT licensed](LICENSE). Hardware research builds on [LogoLight](https://github.com/Ark0N/LogoLight) and [iFixit's teardown](https://www.ifixit.com/News/120152/we-tore-down-the-macbook-proled-xdr-and-found-the-secret-of-the-glowing-apple). Adapted code retains its [third-party notice](ThirdParty/LogoLight-LICENSE.txt).

Glow is not affiliated with Apple. Apple and MacBook are trademarks of Apple Inc.
