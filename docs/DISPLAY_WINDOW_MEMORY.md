# Display window memory in this fork

The Window layout settings contain two independent options, both off by default:

- Remember a window's size separately for each connected display. When an open
  window first appears on another display, apply its learned size within the
  visible area (excluding the Dock and menu bar).
- Remember the last visible arrangement on each display. After a display
  reconnects, move and resize matching windows that are still open. Closed
  applications, documents and browser tabs are not reopened.

Size memory scans every 0.5 seconds. A new window or display transition receives
one restore attempt, after mouse interaction has ended. Subsequent manual moves
and resizes are observed, never retried against an old target. Accepted geometry
is learned after 1.5 seconds of stability. Applications that reject a size are
not repeatedly forced back to it. Overlapping windows are resolved by their
WindowServer ID, not their position.

Display reconnect notifications are coalesced for 0.6 seconds. Reconnection
placement also waits for mouse interaction to finish, and a restored layout
consumes the size transition so the two options do not apply competing frames.
These are scheduling intervals, not guarantees of application response time.

Both options require Accessibility permission and stop their observer and timer
when turned off or when the Window layout feature is removed. Display geometry,
size profiles and title digests are kept in this Mac's preferences and excluded
from exported settings backups. Window titles are hashed with a local salt;
the snapshots do not store window contents.

The implementation draws on the display-specific size and layout behavior of
[Tsubame](https://github.com/zembutsu/tsubame), licensed under MIT. See
[`Tsubame-LICENSE`](../ThirdParty/Tsubame-LICENSE). It is implemented as a
separate service to keep changes to upstream Vorssaint files small.

To bring in upstream changes while keeping this feature, fetch `upstream/main`
and merge it into `feature/display-window-memory`, resolve any conflicts, then
run `./build.sh`, the Window Layout test suite, and a physical display
disconnect/reconnect check. Git cannot guarantee conflict-free updates.
