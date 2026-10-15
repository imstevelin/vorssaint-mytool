# vorssaint-imstevelin release

This is an unofficial fork of [Vorssaint](https://github.com/vorssaint/vorssaint-utils), maintained at [imstevelin/vorssaint-mytool](https://github.com/imstevelin/vorssaint-mytool). It is not an official Vorssaint build or endorsed by the upstream maintainer. The source remains GPL-3.0-or-later; see `LICENSE` and `TRADEMARKS.md`.

## 1.0.3

- Merge upstream `vorssaint-utils/main` through `794608a5` (44 commits), including recorder, clipboard, switcher, Dynamic Island, command bar, and settings fixes. Keep the fork's display memory, Bluetooth recovery, preference migration, branding, and update channel.
- Fix display size memory fighting manual window movement and resizing: apply a saved frame once per new window or display transition, wait for mouse interaction to finish, and learn the accepted size after it settles. Never retry an old frame when an app enforces size limits.
- Match Accessibility windows by WindowServer ID instead of position, avoiding changes to another overlapping window. Avoid redundant position writes on size-only changes.
- Reduce size detection polling from 3 seconds to 0.5 seconds and display-change debounce from 3 seconds to 0.6 seconds. Actual application response time varies.

## 1.0.2

- Optional Bluetooth speaker recovery in Sound Output Switcher settings. After one administrator authorization, a new Bluetooth default output can restart `bluetoothd` with a narrowly scoped command.
- Short disconnects, a persisted cooldown, and a reconnect marker prevent a restart loop. The feature is off by default and its authorization can be removed in Settings or during a full uninstall.

## 1.0.1

- On first launch, import compatible explicit preferences from the official Vorssaint app on the same Mac. The official preferences stay unchanged. If this fork has already completed setup, its own choices take priority.
- Reinstalling the app bundle keeps the fork’s preferences and private files. A deliberate full uninstall still removes them. macOS permissions belong to the fork’s bundle ID and may need to be granted once.
- Existing official settings backup files can be imported in Advanced Settings; older backups preserve the fork’s display memory switches.

## 1.0.0

- Two independent Window Layout switches: remember each app window’s size per display, and restore still-open windows to their saved size and position when a display reconnects.
- Separate bundle identity, icon, update feed, and manual update path for this fork.

## Build and update

Run `./build.sh` and `./Tools/make-dmg.sh` on macOS with Xcode or Command Line Tools. The bundle is `vorssaint-imstevelin.app` with bundle identifier `com.imstevelin.vorssaint-imstevelin` and a fork-specific icon. The release build uses the local Apple Development signing identity when present. This identity is not a Developer ID distribution certificate, and the DMG is not notarized. A Mac may require a manual Open action in System Settings after download.

The app checks only this fork's GitHub Releases. Its update button opens the fork's release page for manual installation. It never runs the upstream automatic installer, whose signature check is tied to the upstream team and bundle ID.

To incorporate upstream changes, fetch `upstream/main` and merge it into the fork's development branch, test the display modules, then merge the development branch into this release branch. Resolve branding and localization conflicts in the release branch before building and tagging a new release.
