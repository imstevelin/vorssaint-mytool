# Volume feedback sound

The shared “Play feedback when changing volume” checkbox is available in the
mixer options (menu panel and island) and external-display audio controls.
Without an explicit choice it inherits macOS volume feedback. A saved choice
overrides that inherited value for adjustments handled by this tool and is
included in settings backups. It does not change the macOS global preference.

The tool uses macOS's volume.aiff and uses the current system media output,
rather than the separate sound-effects output. Playback gain is unity: native
CoreAudio gain or the monitor's physical DDC gain supplies the actual loudness.
Applying the reported volume to the sound again would attenuate it twice.

Island and DDC keys issue feedback for each accepted input immediately, using the
published DDC intent or predicted native key level. They do not wait for hardware
write/readback completion, and completion never replays a click. Shift retains
its normal override, and mute/zero stay silent. Failed synchronous submissions
are skipped. The hardware write path and native fallback remain independent.

The old NSSound stop/play path was measured on this Mac at about 240 ms per play,
plus 14-17 ms per stop, on the UI thread. A 60 ms main-thread FIFO further delayed
bursts. Both have been removed. Audio is now a preloaded PCM buffer on a persistent
AVAudioEngine/AVAudioPlayerNode, with preparation and interrupting buffer scheduling
on a dedicated user-interactive serial queue. No audio operations execute on main,
no deliberate inter-click wait exists, and each input starts a fresh buffer attack.
Output changes and disabling the option invalidate stale queued requests; the
engine is prewarmed during output/session changes and stopped when disabled.

Production sound scheduling and key routing run against controlled audio/queue
boundaries in SystemOutputControlTests and NotchVolumeRoutingTests; no test
changes the user's hardware volume or plays audio.

Latency validation used the actual audio backend with only its node gain set to
zero to avoid audible test sounds. Buffer scheduling measured 0.014-0.075 ms,
with a maximum main-run-loop heartbeat gap of 16.23 ms during background setup
and ten clicks. These measure API execution and UI-thread responsiveness, not
physical keyboard-to-speaker latency. Logs and silent probes are saved at
`/tmp/mytool-volume-latency-before.log`, `/tmp/mytool-volume-latency-after.log`,
`/tmp/mytool-volume-engine-probe.swift`, and `/tmp/mytool-volume-service-probe.swift`.

A second silent harness exercised the complete production feedback service and
audio backend for 20 timed inputs. Main-thread input handling measured
0.012-0.091 ms, and its maximum 5 ms heartbeat gap was 6.53 ms. This also covers
background prewarming and the dispatch boundary, rather than buffer scheduling
alone. Log: `/tmp/mytool-volume-service-latency.log`.
