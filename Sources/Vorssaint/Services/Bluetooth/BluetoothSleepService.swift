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

/// Restarts bluetoothd once when a selected Bluetooth speaker becomes the default audio
/// output. A short route loss during the restart is part of the same episode.
/// The persisted cooldown also covers app crashes and relaunches.
final class BluetoothAudioRecoveryService {
    static let shared = BluetoothAudioRecoveryService()
    static let rulePath = "/etc/sudoers.d/vorssaint-imstevelin-bluetooth-audio"
    private static let command = ["-n", "/usr/bin/pkill", "-x", "bluetoothd"]
    private var timer: Timer?
    private var policy = BluetoothAudioRecoveryPolicy()
    private var routeListener: AudioObjectPropertyListenerBlock?
    private var routeWork: DispatchWorkItem?
    private var authorizationInFlight = false
    private var generation = 0

    private static var routeAddresses: [AudioObjectPropertyAddress] {
        [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices].map {
            AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
        }
    }

    private func installRouteListener() -> Bool {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.timer != nil, self.routeWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.routeWork = nil
                self?.sampleRoute()
            }
            self.routeWork = work
            DispatchQueue.main.async(execute: work)
        }
        var installed: [AudioObjectPropertyAddress] = []
        for var address in Self.routeAddresses {
            guard AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr else {
                for var previous in installed {
                    AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &previous, .main, listener)
                }
                return false
            }
            installed.append(address)
        }
        routeListener = listener
        return true
    }

    private func removeRouteListener() {
        if let routeListener {
            for var address in Self.routeAddresses {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, routeListener)
            }
        }
        routeListener = nil
        routeWork?.cancel(); routeWork = nil
    }


    private init() {}

    static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: rulePath)
            && Shell.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pkill", "-x", "bluetoothd"],
                         timeout: 3).status == 0
    }

    static func install(completion: @escaping (Bool) -> Void) {
        let rule = "#\(getuid()) ALL=(root) NOPASSWD: /usr/bin/pkill -x bluetoothd"
        let command = "mkdir -p /etc/sudoers.d && chmod 0755 /etc/sudoers.d && echo '\(rule)' > \(rulePath) && chmod 0440 \(rulePath) && /usr/sbin/visudo -c -f \(rulePath) || { rm -f \(rulePath); exit 1; }"
        AdminShell.run(command, prompt: "Allow 實用小工具 to restart Bluetooth once when a speaker connects") { ok in
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
            generation += 1
            removeRouteListener()
            return
        }
        guard timer == nil else { return }
        _ = installRouteListener()
        // Notifications accelerate changes; keep the original three-second
        // fallback even when registration succeeds. A missed driver event
        // must not make speaker recovery slower than the previous release.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.sampleRoute()
        }
        sampleRoute()
    }

    private func sampleRoute(now: Date = Date()) {
        // Do not consume another device's policy episode while authorizing
        // the previous one. Re-sample after authorization completes.
        guard !authorizationInFlight else { return }
        let uid = Self.defaultBluetoothOutputUID()
        let defaults = UserDefaults.standard
        let previousTime = defaults.double(forKey: DefaultsKey.bluetoothAudioRecoveryLastAttempt)
        let shouldAttempt = policy.observe(uid: uid, now: now,
                                           previousAttempt: previousTime > 0
                                               ? Date(timeIntervalSince1970: previousTime) : nil,
                                           selectedUIDs: Set(Self.selectedDevices.keys))
        guard let uid else { return }
        if defaults.string(forKey: DefaultsKey.bluetoothAudioRecoveryAwaitingReconnectUID) == uid {
            // Suppress the first post-restart connection even if the daemon was
            // unavailable longer than the ordinary cooldown.
            if shouldAttempt || policy.reconnectedWithinEpisode {
                defaults.removeObject(forKey: DefaultsKey.bluetoothAudioRecoveryAwaitingReconnectUID)
            }
            return
        }
        guard shouldAttempt, !authorizationInFlight else { return }
        authorizationInFlight = true
        let currentGeneration = generation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let configured = Self.isConfigured // May invoke sudo; never wait on main.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.authorizationInFlight = false
                defer { if self.timer != nil { self.sampleRoute() } }
                guard configured, self.generation == currentGeneration, self.timer != nil,
                      Self.defaultBluetoothOutputUID() == uid,
                      AppFeature.soundOutputSwitcher.isAvailable,
                      defaults.bool(forKey: DefaultsKey.bluetoothAudioRecoveryEnabled),
                      Self.selectedDevices[uid] != nil else { return }
                // Persist the loop guard before invoking the daemon restart.
                defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.bluetoothAudioRecoveryLastAttempt)
                defaults.set(uid, forKey: DefaultsKey.bluetoothAudioRecoveryAwaitingReconnectUID)
                DispatchQueue.global(qos: .utility).async {
                    guard AppFeature.soundOutputSwitcher.isAvailable,
                          defaults.bool(forKey: DefaultsKey.bluetoothAudioRecoveryEnabled),
                          Self.selectedDevices[uid] != nil else { return }
                    _ = Shell.run("/usr/bin/sudo", Self.command, timeout: 10)
                }
            }
        }
    }

    /// Names are labels only. Matching always uses the exact Core Audio UID.
    static var selectedDevices: [String: String] {
        let raw = UserDefaults.standard.dictionary(forKey: DefaultsKey.bluetoothAudioRecoveryDevices) ?? [:]
        return raw.reduce(into: [:]) { result, item in
            guard !item.key.isEmpty, let name = item.value as? String else { return }
            result[item.key] = name.isEmpty ? item.key : name
        }
    }

    struct Device: Identifiable {
        let uid: String
        let name: String
        var id: String { uid }
    }

    /// Core Audio exposes Bluetooth playback endpoints once they are connected.
    /// Selections keep their names locally so disconnected devices remain editable.
    static func availableBluetoothOutputs() -> [Device] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !ids.isEmpty else { return [] }
        let status = ids.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return [] }
        var seen = Set<String>()
        return ids.compactMap { id -> Device? in
            guard isBluetooth(id), let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  seen.insert(uid).inserted else { return nil }
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { return nil }
            return Device(uid: uid, name: stringProperty(id, kAudioObjectPropertyName) ?? uid)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func defaultBluetoothOutputUID() -> String? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr,
              device != AudioObjectID(kAudioObjectUnknown), isBluetooth(device) else { return nil }
        return stringProperty(device, kAudioDevicePropertyDeviceUID)
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func stringProperty(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr else { return nil }
        let result = value as String
        return result.isEmpty ? nil : result
    }
}
