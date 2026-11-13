# Glow 0.1.0 beta — draft

A small native menu-bar app for focused work, daily progress and Apple-logo light experiments.

[Apple Silicon ZIP — available when this release is published](https://github.com/Blacklord100/glow/releases/download/v0.1.0/Glow-0.1.0-arm64.zip)

**Requires macOS 14 or later and an Apple Silicon Mac.** Unzip, move `Glow.app` to Applications, and open it. Use the Glow menu-bar item to reopen the dashboard after closing its window.

**Notarization: pending validation.**

Signed binaries are being prepared for release. Downloads will be published after Apple notarization and final validation succeed.

## Included

- Daily Charge with a growing on-screen Apple and menu-bar progress meter.
- 25-, 45- and 60-minute focus sessions, pause/resume, an adjustable daily goal and manual offline time.
- Seven-day focus history, saved locally.
- Breathe, Pulse, Daily Charge, System Default and Off previews.
- Optional launch at login.
- Read-only Logo Lab diagnostics and a simulated height-fill experiment.

## Physical lighting and beta limits

Physical effects require a detected compatible PROLED MacBook logo controller and must be enabled each launch. They use private macOS interfaces and have not yet been validated on compatible logo hardware. Daily Charge uses milestone pulses; individual LED control and physical height-fill effects are not implemented.

Development testing was performed on macOS 26.6.2. Older supported macOS versions still need device testing. The focus tracker and previews remain usable on Macs without an illuminated logo.

The app stores focus history and preferences locally and does not record screen contents, keystrokes, apps or websites.

If a DMG is attached, consult its final release validation status: the Xcode notarization route supplies a signed DMG containing the stapled app, without separately notarizing the DMG container. The ZIP is the primary download.

Source is available under the MIT license. Third-party notices are included in the app.
