// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind Bluetooth on sleep, kept free of AppKit and IOKit so
/// they can be tested directly.
///
/// The rule the whole feature turns on: Vorssaint only ever puts back what it
/// took away. Bluetooth already off when the Mac went to sleep is never
/// switched on for the user, which is the part a plain sleep-and-wake toggle
/// gets wrong.
enum BluetoothSleepSupport {
    /// What to do as the Mac goes to sleep.
    struct SleepPlan: Equatable {
        /// Whether Bluetooth should be switched off now.
        let powersOff: Bool
        /// Whether a later wake owes the user a restore.
        let owesRestore: Bool
    }

    static func sleepPlan(isPoweredOn: Bool, restoresOnWake: Bool) -> SleepPlan {
        guard isPoweredOn else { return SleepPlan(powersOff: false, owesRestore: false) }
        return SleepPlan(powersOff: true, owesRestore: restoresOnWake)
    }

    /// Whether waking (or a launch that finds a restore still owed, because
    /// the Mac was shut down while asleep) should switch Bluetooth back on.
    /// Bluetooth the user turned on themselves in the meantime is left alone.
    /// Every launch asks, so the controller is read only when a restore is owed.
    static func restores(owesRestore: Bool, isPoweredOn: @autoclosure () -> Bool) -> Bool {
        owesRestore && !isPoweredOn()
    }
}

/// One attempt per connection episode, with a persisted minimum interval.
/// Route losses shorter than ten minutes (including bluetoothd's own restart)
/// stay in the same episode.
struct BluetoothAudioRecoveryPolicy {
    static let cooldown: TimeInterval = 30 * 60
    static let disconnectThreshold: TimeInterval = 10 * 60
    private(set) var sampledInitialRoute = false
    private(set) var lastConnectedUID: String?
    private(set) var reconnectedWithinEpisode = false
    private var absentSince: Date?

    mutating func observe(uid: String?, now: Date, previousAttempt: Date?,
                          selectedUIDs: Set<String>) -> Bool {
        reconnectedWithinEpisode = false
        if !sampledInitialRoute {
            sampledInitialRoute = true
            lastConnectedUID = uid
            return false
        }
        guard let uid else {
            if lastConnectedUID != nil {
                if absentSince == nil { absentSince = now }
                if let absentSince, now.timeIntervalSince(absentSince) >= Self.disconnectThreshold {
                    lastConnectedUID = nil
                }
            }
            return false
        }
        let wasAbsent = absentSince != nil
        absentSince = nil
        guard uid != lastConnectedUID else {
            reconnectedWithinEpisode = wasAbsent
            return false
        }
        lastConnectedUID = uid
        guard selectedUIDs.contains(uid) else { return false }
        // Bluetooth may re-enumerate with a different Core Audio UID after a
        // daemon restart, so the minimum interval applies across all devices.
        if let previousAttempt, now.timeIntervalSince(previousAttempt) < Self.cooldown { return false }
        return true
    }
}
