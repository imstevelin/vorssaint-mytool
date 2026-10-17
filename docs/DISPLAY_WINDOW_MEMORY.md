# Display window memory in this fork

The Window layout settings contain two independent options, both off by default:

- Remember a window's size and position separately for each connected display.
  When a window reopens or first appears on another display, restore its learned
  frame within the visible area (excluding the Dock and menu bar). Windowed
  maximum is remembered too; true fullscreen remains excluded.
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

## 1.0.4 fixes

Open windows receive one new size restore after any display topology or usable
resolution change, including when their display ID is unchanged. Hidden windows
consume that transition when they become visible. Learning pauses during topology
settling. Layout restoration consumes the same generation to avoid competing writes.

Both learning and restoration require an AX standard, non-modal, resizable window
with a minimize button. Dialogs, sheets, floating palettes and fullscreen windows
are excluded before fallback matching and checked again before writes. Apps that
do not expose this metadata are conservatively skipped.

Normal opening profiles exclude half, quarter, and common third-width
tiling geometry (including macOS margins). Windowed maximum is saved separately
from temporary tiling. Arrangement snapshots may still retain
these positions for explicit reconnect layout restoration. Legacy sizes that match
those geometries are ignored; if a normal size was already overwritten by an older
version, resize the main window normally once to teach it again.

## HiDPI reconnect latency (2026-10-18)

The HiDPI auto-resume used a three-second trailing debounce, followed by a
0.6-second memory settle and the ordinary 0.5-second polling cycle. Repeated
screen notifications could restart the first wait. Managed transitions also
cleared the pending reconnect layout, losing its restoration offer.

Auto-resume now coalesces notifications into one fixed 0.5-second wait from the
first event. After HiDPI verifies its final mode, display memory retains the
pending reconnect offer, merges any newly discovered physical displays, drops
disconnected ones, and schedules a scan after 0.2 seconds. The two-second pause
still applies to learning new geometry, rather than delaying restoration. Mouse
interaction suppression and one-shot restoration remain in place. Stopped or
superseded transitions cannot run an old scheduled scan.

The production scheduling and transition methods are compiled into
`DisplayReconnectTimingTests`; tests cover notification bursts, subsequent
reconnects, preserved/dropped layout offers, learning versus restoration delays,
and stale or stopped callbacks. Display-restoration, window-layout and features
suites pass 1,869 checks in total.

Installed runtime validation: the signed release starts successfully, auto-resumes
its saved HiDPI session, and macOS reports PA328QV / the virtual source at
2560×1440 HiDPI (5120×2880 rendering) @ 75Hz. A read-only mode probe observed the
virtual desktop appear about 1.83 seconds after detecting app launch; this is an
auto-resume startup measurement, not a physical cable reconnect or a measured
window-resize completion time. Logs: `/tmp/mytool-display-reconnect-runtime.log`,
`/tmp/mytool-display-reconnect-after.json`, `/tmp/mytool-display-reconnect-tests.log`.
No physical cable disconnect/reconnect was performed in this run.

## Opening size and position (2026-10-18)

Opening profiles now store the complete frame relative to the physical display,
independently of reconnect snapshots. Closing a window no longer removes its
learned opening position. A changed browser title falls back to the last learned
frame for that app on that display. A position-only difference also triggers
restoration, preserving a manually chosen gap above the Dock.

An exact windowed maximum restores to the current usable area, including after
a resolution or Dock change. Near-maximum frames retain their original insets.
Temporary tiles still do not replace opening profiles. Older size-only preferences
remain readable and usable, but cannot shrink an already maximized opening window.
Resize or position the window and let it settle for 1.5 seconds once to teach the
new complete profile. Smaller work areas clamp frames only as needed.
