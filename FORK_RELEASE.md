# vorssaint-imstevelin release

This is an unofficial fork of [Vorssaint](https://github.com/vorssaint/vorssaint-utils), maintained at [imstevelin/vorssaint-mytool](https://github.com/imstevelin/vorssaint-mytool). It is not an official Vorssaint build or endorsed by the upstream maintainer. The source remains GPL-3.0-or-later; see `LICENSE` and `TRADEMARKS.md`.

## 1.0.0

- Two independent Window Layout switches: remember each app window’s size per display, and restore still-open windows to their saved size and position when a display reconnects.
- Separate bundle identity, icon, update feed, and manual update path for this fork.

## Build and update

Run `./build.sh` and `./Tools/make-dmg.sh` on macOS with Xcode or Command Line Tools. The bundle is `vorssaint-imstevelin.app` with bundle identifier `com.imstevelin.vorssaint-imstevelin` and a fork-specific icon. The release build uses the local Apple Development signing identity when present. This identity is not a Developer ID distribution certificate, and the DMG is not notarized. A Mac may require a manual Open action in System Settings after download.

The app checks only this fork's GitHub Releases. Its update button opens the fork's release page for manual installation. It never runs the upstream automatic installer, whose signature check is tied to the upstream team and bundle ID.

To incorporate upstream changes, fetch `upstream/main` and merge it into the fork's development branch, test the display modules, then merge the development branch into this release branch. Resolve branding and localization conflicts in the release branch before building and tagging a new release.
