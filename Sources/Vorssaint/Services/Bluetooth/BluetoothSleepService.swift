// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio
import IOKit

/// Switches Bluetooth off while the Mac sleeps, so a closed laptop in a bag
/// stops grabbing the headphones the user is listening to elsewhere.
///
/// Unlike the plain sleep-and-wake toggle, the restore is honest: the state
/// found before sleep is remembered, so Bluetooth the user had already turned
/// off is never switched back on for them. The memory is a preference rather
/// than a variable, so a Mac shut down while asleep still gets its Bluetooth
/// back on the next launch instead of staying dark.
///
/// Nothing runs while the feature is off: no observers, no polling, no cost.
final class BluetoothSleepService {
    static let shared = BluetoothSleepService()

    /// A Bluetooth controller is soldered in or it is not; the answer cannot
    /// change while the Mac is running, so resolve it once.
    static let isSupported: Bool = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOBluetoothHCIController"))
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }()

    private var observers: [NSObjectProtocol] = []

    private init() {}

    func syncWithPreferences() {
        guard Self.isSupported else { return }
        // A restore still owed here means an earlier run switched Bluetooth
        // off and never saw the wake, because the Mac was shut down (or the
        // app quit) while it slept. The debt is paid before anything else,
        // and paid even when the feature has since been switched off, so
        // nothing Vorssaint took away is ever kept.
        restoreIfOwed()
        if AppFeature.bluetoothSleep.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.bluetoothSleepEnabled) {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.macWillSleep()
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.restoreIfOwed()
            },
        ]
    }

    func stop() {
        guard !observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }

    private func macWillSleep() {
        let defaults = UserDefaults.standard
        let plan = BluetoothSleepSupport.sleepPlan(
            isPoweredOn: Self.isPoweredOn,
            restoresOnWake: defaults.bool(forKey: DefaultsKey.bluetoothSleepRestoreOnWake))
        defaults.set(plan.owesRestore, forKey: DefaultsKey.bluetoothSleepRestorePending)
        if plan.powersOff { Self.setPowered(false) }
    }

    private func restoreIfOwed() {
        let defaults = UserDefaults.standard
        let restores = BluetoothSleepSupport.restores(
            owesRestore: defaults.bool(forKey: DefaultsKey.bluetoothSleepRestorePending),
            isPoweredOn: Self.isPoweredOn)
        // The debt is settled either way: Bluetooth the user switched on
        // themselves cancels it instead of waiting for the next sleep.
        defaults.set(false, forKey: DefaultsKey.bluetoothSleepRestorePending)
        if restores { Self.setPowered(true) }
    }

    // MARK: Controller power

    private typealias PowerGet = @convention(c) () -> Int32
    private typealias PowerSet = @convention(c) (Int32) -> Void

    /// The Bluetooth controller's power switch, the same pair the menu bar
    /// item uses. Resolved once and guarded: without it the feature simply
    /// does nothing rather than pretending to work.
    private static let controllerPower: (get: PowerGet, set: PowerSet)? = {
        let path = "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth"
        guard let handle = dlopen(path, RTLD_LAZY),
              let getSymbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState"),
              let setSymbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { return nil }
        return (unsafeBitCast(getSymbol, to: PowerGet.self),
                unsafeBitCast(setSymbol, to: PowerSet.self))
    }()

    private static var isPoweredOn: Bool {
        guard let controllerPower else { return false }
        return controllerPower.get() != 0
    }

    private static func setPowered(_ on: Bool) {
        controllerPower?.set(on ? 1 : 0)
    }
}

/// Restarts bluetoothd once when a Bluetooth speaker becomes the default audio
/// output. A short route loss during the restart is part of the same episode.
/// The persisted cooldown also covers app crashes and relaunches.
final class BluetoothAudioRecoveryService {
    static let shared = BluetoothAudioRecoveryService()
    static let rulePath = "/etc/sudoers.d/vorssaint-imstevelin-bluetooth-audio"
    private static let command = ["-n", "/usr/bin/pkill", "-x", "bluetoothd"]
    private var timer: Timer?
    private var policy = BluetoothAudioRecoveryPolicy()

    private init() {}

    static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: rulePath)
            && Shell.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pkill", "-x", "bluetoothd"],
                         timeout: 3).status == 0
    }

    static func install(completion: @escaping (Bool) -> Void) {
        let rule = "#\(getuid()) ALL=(root) NOPASSWD: /usr/bin/pkill -x bluetoothd"
        let command = "mkdir -p /etc/sudoers.d && chmod 0755 /etc/sudoers.d && echo '\(rule)' > \(rulePath) && chmod 0440 \(rulePath) && /usr/sbin/visudo -c -f \(rulePath) || { rm -f \(rulePath); exit 1; }"
        AdminShell.run(command, prompt: "Allow vorssaint-imstevelin to restart Bluetooth once when a speaker connects") { ok in
            completion(ok && isConfigured)
        }
    }

    static func remove(completion: @escaping (Bool) -> Void) {
        guard FileManager.default.fileExists(atPath: rulePath) else { completion(true); return }
        AdminShell.run("/bin/rm -f \(rulePath)", prompt: "Remove Bluetooth recovery authorization") {
            completion($0 && !FileManager.default.fileExists(atPath: rulePath))
        }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.soundOutputSwitcher.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.bluetoothAudioRecoveryEnabled)
        guard enabled else {
            timer?.invalidate()
            timer = nil
            policy = BluetoothAudioRecoveryPolicy()
            return
        }
        guard timer == nil else { return }
        sampleRoute()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.sampleRoute()
        }
    }

    private func sampleRoute(now: Date = Date()) {
        let uid = Self.defaultBluetoothOutputUID()
        let defaults = UserDefaults.standard
        let previousTime = defaults.double(forKey: DefaultsKey.bluetoothAudioRecoveryLastAttempt)
        let shouldAttempt = policy.observe(uid: uid, now: now,
                                           previousAttempt: previousTime > 0
                                               ? Date(timeIntervalSince1970: previousTime) : nil)
        guard let uid else { return }
        if defaults.string(forKey: DefaultsKey.bluetoothAudioRecoveryAwaitingReconnectUID) == uid {
            // Suppress the first post-restart connection even if the daemon was
            // unavailable longer than the ordinary cooldown.
            if shouldAttempt || policy.reconnectedWithinEpisode {
                defaults.removeObject(forKey: DefaultsKey.bluetoothAudioRecoveryAwaitingReconnectUID)
            }
            return
        }
        guard shouldAttempt, Self.isConfigured else { return }
        // Write the guard before killing the daemon: even if the app exits,
        // its reconnect cannot start another restart loop.
        defaults.set(now.timeIntervalSince1970, forKey: DefaultsKey.bluetoothAudioRecoveryLastAttempt)
        defaults.set(uid, forKey: DefaultsKey.bluetoothAudioRecoveryAwaitingReconnectUID)
        DispatchQueue.global(qos: .utility).async {
            _ = Shell.run("/usr/bin/sudo", Self.command, timeout: 10)
        }
    }

    private static func defaultBluetoothOutputUID() -> String? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &size, &device) == noErr,
              device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &size, &transport) == noErr,
              transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        else { return nil }
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr else { return nil }
        let result = uid as String
        return result.isEmpty ? nil : result
    }
}
