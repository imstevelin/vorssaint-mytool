// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import VirtualDisplayBridge
#if canImport(DisplayRecoverySupport)
import DisplayRecoverySupport
#endif

/// Owns only this app's virtual displays. Physical IDs remain the DDC address.
final class VirtualHiDPIService: ObservableObject {
    static let shared = VirtualHiDPIService()
    private static let ownershipLock = NSLock()
    private static var physicalByVirtual: [CGDirectDisplayID: CGDirectDisplayID] = [:]
    private static var physicalRates: [CGDirectDisplayID: Double] = [:]
    private static var physicalSizes: [CGDirectDisplayID: CGSize] = [:]
    static func recordPhysicalSize(_ id: CGDirectDisplayID, width: Int, height: Int, rate: Double) {
        ownershipLock.withLock {
            physicalSizes[id] = CGSize(width: width, height: height)
            // A zero refresh rate means unknown/variable, not a request for 0 Hz.
            if rate.isFinite, rate >= 24, rate <= 240 { physicalRates[id] = rate }
        }
    }
    static func isOwnedDisplay(_ id: CGDirectDisplayID) -> Bool {
        ownershipLock.withLock { physicalByVirtual[id] != nil }
    }
    static func physicalDisplay(for id: CGDirectDisplayID) -> CGDirectDisplayID {
        ownershipLock.withLock { physicalByVirtual[id] ?? id }
    }
    static func desktopDisplay(for id: CGDirectDisplayID) -> CGDirectDisplayID {
        ownershipLock.withLock { physicalByVirtual.first { $0.value == id }?.key ?? id }
    }
    struct Profile: Codable, Equatable {
        var width: Int
        var height: Int
        var rate: Double
    }
    struct Session {
        let uuid: String
        let physicalID: CGDirectDisplayID
        let virtualID: CGDirectDisplayID?
        let profile: Profile
        let original: DisplayRecoverySnapshot
    }
    @Published private(set) var sessions: [CGDirectDisplayID: Session] = [:]
    @Published private(set) var switching: CGDirectDisplayID?
    @Published private(set) var confirmationDisplay: CGDirectDisplayID?
    @Published private(set) var secondsRemaining = 0
    @Published private(set) var failure: String?
    var available: Bool { VSDVirtualDisplayAvailable() }
    private var baseline: DisplayRecoverySnapshot?
    private var journal: DisplayRecoveryJournal?
    private var journalURL: URL?
    private var watchdog: Process?
    private var hosts: [CGDirectDisplayID: Process] = [:]
    private var hostRequests: [CGDirectDisplayID: URL] = [:]
    private var timer: Timer?
    private var generation = 0
    private var resumeWork: DispatchWorkItem?
    private var automaticConfirmation = false
    private var verificationPasses: [CGDirectDisplayID: Int] = [:]
    private var expectedColorProfiles: [CGDirectDisplayID: Data] = [:]
    private var autoAttempted = Set<String>()
    var hasPendingRecovery: Bool { baseline != nil && sessions.isEmpty && switching == nil }
    private var observers: [NSObjectProtocol] = []
    private let profilesKey = "virtualHiDPIProfilesLocalV1"

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.topologyChanged() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.autoAttempted.removeAll()
                self?.topologyChanged()
            }
        })
    }

    func presets(for id: CGDirectDisplayID) -> [Profile] {
        // Called by SwiftUI bodies; never ask WindowServer while it is reconfiguring.
        let size = Self.ownershipLock.withLock { Self.physicalSizes[id] } ?? CGSize(width: 1920, height: 1080)
        let width = Int(size.width), height = Int(size.height)
        let rate = sessions[id]?.profile.rate ?? Self.ownershipLock.withLock { Self.physicalRates[id] } ?? 60
        let aspect = Double(width) / Double(max(1, height))
        let widths = width < height ? [width, 1440, 1080, 900, 720] : [width, 2560, 1920, 1600, 1280, 960]
        var used = Set<Int>()
        return widths.compactMap { w in
            let h = Int((Double(w) / aspect).rounded())
            guard used.insert(w).inserted, Self.valid(width: w, height: h, rate: rate) else { return nil }
            return Profile(width: w, height: h, rate: rate)
        }
    }

    func defaultProfile(for id: CGDirectDisplayID) -> Profile {
        if let session = sessions[id] { return session.profile }
        return presets(for: id).first ?? Profile(width: 1920, height: 1080, rate: 60)
    }

    func refreshRates(for id: CGDirectDisplayID) -> [Double] {
        // Include fractional and uncommon physical rates so the picker can
        // represent the default exactly, without rounding it to a fixed preset.
        Array(Set([30.0, 50.0, 60.0, 75.0, 90.0, 120.0, 144.0, defaultProfile(for: id).rate])).sorted()
    }

    static func valid(width: Int, height: Int, rate: Double) -> Bool {
        width >= 640 && height >= 480 && width <= 5120 && height <= 5120
            && width * height <= 14_745_600 && rate.isFinite && rate >= 24 && rate <= 240
    }

    func enable(_ id: CGDirectDisplayID, profile: Profile, preferNative: Bool = true,
                automaticallyConfirm: Bool = false) {
        guard switching == nil, confirmationDisplay == nil, sessions[id] == nil,
              CGDisplayIsBuiltin(id) == 0, CGDisplayIsOnline(id) != 0,
              let uuid = DisplayRecoverySnapshot.uuid(id),
              Self.valid(width: profile.width, height: profile.height, rate: profile.rate) else { return }
        guard let colorProfile = DisplayColorProfile.data(for: id) else {
            failure = DisplayControlText.text("無法讀取螢幕色彩描述檔，已取消 HiDPI", "Cannot read the display color profile; HiDPI cancelled")
            return
        }
        expectedColorProfiles[id] = colorProfile
        verificationPasses[id] = 0
        failure = nil
        automaticConfirmation = automaticallyConfirm
        let original = DisplayRecoverySnapshot.capture()
        guard original.screens.filter({ $0.uuid == uuid }).count == 1 else {
            failure = DisplayControlText.text("顯示器識別不唯一，請先重新連接螢幕", "Display identity is ambiguous; reconnect the monitor first")
            return
        }
        guard original.restore() else {
            failure = DisplayControlText.text("目前顯示模式無法安全復原，已取消切換", "Current display mode cannot be safely restored; switching cancelled"); return
        }
        do { try armRecovery(snapshot: original) }
        catch { failure = error.localizedDescription; return }
        generation += 1
        let token = generation
        switching = id
        DisplayWindowMemoryService.shared.beginManagedDisplayTransition()
        // Start only after the child acknowledges it has loaded the rollback journal.
        waitForWatchdog(id: id, uuid: uuid, profile: profile, original: original, token: token, attempts: 0, preferNative: preferNative)
    }

    private func waitForWatchdog(id: CGDirectDisplayID, uuid: String, profile: Profile,
                                 original: DisplayRecoverySnapshot, token: Int, attempts: Int, preferNative: Bool) {
        guard token == generation else { return }
        guard let url = journalURL, watchdog?.isRunning == true else {
            abortCreation(id, original: original, virtual: nil, message: "Display recovery helper unavailable")
            return
        }
        guard FileManager.default.fileExists(atPath: url.appendingPathExtension("ready").path) else {
            if attempts >= 30 {
                abortCreation(id, original: original, virtual: nil, message: "Display recovery helper timed out")
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.waitForWatchdog(id: id, uuid: uuid, profile: profile, original: original,
                                          token: token, attempts: attempts + 1, preferNative: preferNative)
                }
            }
            return
        }
        let modes = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
        if preferNative, let native = modes.first(where: { Self.matches($0, profile: profile) }),
           CGDisplaySetDisplayMode(id, native, nil) == .success,
           let actual = CGDisplayCopyDisplayMode(id), Self.matches(actual, profile: profile) {
            sessions[id] = Session(uuid: uuid, physicalID: id, virtualID: nil, profile: profile, original: original)
            awaitVerification(id, token: token, attempts: 0)
            return
        }
        guard available else {
            abortCreation(id, original: original, virtual: nil, message: DisplayControlText.unavailable); return
        }
        // Creation belongs to a child so CoreGraphics in this process can read its modes.
        let serial = uuid.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        let requestURL = url.appendingPathExtension("host-\(id)")
        let request = VirtualDisplayHostRequest(parentPID: getpid(), width: UInt32(profile.width),
            height: UInt32(profile.height), rate: profile.rate, serial: serial, name: "實用小工具 HiDPI", colorProfile: expectedColorProfiles[id])
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/VirtualDisplayHost")
        process.arguments = [requestURL.path]
        do {
            try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
            try process.run()
            hosts[id] = process; hostRequests[id] = requestURL
            journal?.hostPIDs = hosts.values.map(\.processIdentifier)
            if let journal, let journalURL { try journal.save(to: journalURL) }
            waitForHost(id: id, uuid: uuid, profile: profile, original: original, token: token, attempts: 0)
        } catch { abortCreation(id, original: original, virtual: nil, message: error.localizedDescription) }
    }

    private func waitForHost(id: CGDirectDisplayID, uuid: String, profile: Profile,
                             original: DisplayRecoverySnapshot, token: Int, attempts: Int) {
        guard token == generation else { return }
        if let request = hostRequests[id], let data = try? Data(contentsOf: request.appendingPathExtension("display")),
           let virtual = try? JSONDecoder().decode(CGDirectDisplayID.self, from: data) {
            Self.ownershipLock.withLock { Self.physicalByVirtual[virtual] = id }
            sessions[id] = Session(uuid: uuid, physicalID: id, virtualID: virtual, profile: profile, original: original)
            attachVirtual(id, virtual: virtual, token: token, attempts: 0)
            return
        }
        guard hosts[id]?.isRunning == true, attempts < 50 else {
            abortCreation(id, original: original, virtual: nil, message: "Virtual display host unavailable"); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForHost(id: id, uuid: uuid, profile: profile, original: original, token: token, attempts: attempts + 1)
        }
    }

    private static func matches(_ mode: CGDisplayMode, profile: Profile) -> Bool {
        mode.width == profile.width && mode.height == profile.height
            && mode.pixelWidth == profile.width * 2 && mode.pixelHeight == profile.height * 2
            && (mode.refreshRate == 0 || abs(mode.refreshRate - profile.rate) < 0.6)
    }

    private func attachVirtual(_ id: CGDirectDisplayID, virtual: CGDirectDisplayID, token: Int, attempts: Int) {
        guard token == generation, let session = sessions[id] else { return }
        _ = DisplayRecoverySnapshot.onlineIDs()
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(virtual, options) as? [CGDisplayMode] ?? []
        if DisplayRecoverySnapshot.onlineIDs().contains(virtual) {
            var config: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&config) == .success, let config {
                let origin = CGDisplayBounds(id).origin
                let mode = modes.first(where: { Self.matches($0, profile: session.profile) })
                let modeConfigured = mode.map { CGConfigureDisplayWithDisplayMode(config, virtual, $0, nil) == .success } ?? true
                let configured = modeConfigured && CGConfigureDisplayOrigin(config, virtual, Int32(origin.x), Int32(origin.y)) == .success
                    && CGConfigureDisplayMirrorOfDisplay(config, id, virtual) == .success
                if configured && CGCompleteDisplayConfiguration(config, .forSession) == .success {
                    awaitVerification(id, token: token, attempts: 0); return
                }
                if !configured { CGCancelDisplayConfiguration(config) }
            }
            abortCreation(id, original: session.original, virtual: virtual, message: DisplayControlText.text("HiDPI 鏡像切換失敗", "HiDPI mirroring failed")); return
        }
        guard attempts < 40 else {
            abortCreation(id, original: session.original, virtual: virtual, message: DisplayControlText.text("此連接無法提供所選 HiDPI 模式", "The selected HiDPI mode is unavailable on this connection")); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.attachVirtual(id, virtual: virtual, token: token, attempts: attempts + 1)
        }
    }

    static func stableVerificationCount(valid: Bool, previous: Int) -> Int {
        valid ? min(4, previous + 1) : 0
    }

    private func awaitVerification(_ id: CGDirectDisplayID, token: Int, attempts: Int) {
        guard token == generation, let session = sessions[id] else { return }
        let desktop = session.virtualID ?? id
        // Public mode queries may return nil for a virtual mirror master;
        // the physical follower exposes the mirror group's actual mode.
        let mode = CGDisplayCopyDisplayMode(desktop) ?? CGDisplayCopyDisplayMode(id)
        let colorMatches = expectedColorProfiles[id].map {
            DisplayColorProfile.matches($0, display: desktop) && DisplayColorProfile.matches($0, display: id)
        } == true
        let valid = mode.map { Self.matches($0, profile: session.profile) } == true
            && (session.virtualID == nil || CGDisplayMirrorsDisplay(id) == desktop) && colorMatches
        verificationPasses[id] = Self.stableVerificationCount(valid: valid, previous: verificationPasses[id] ?? 0)
        if verificationPasses[id, default: 0] >= 4 {
            switching = nil
            confirmationDisplay = id
            journal?.deadline = Date().timeIntervalSince1970 + 15
            do { if let journal, let url = journalURL { try journal.save(to: url) } }
            catch {
                abortCreation(id, original: session.original, virtual: session.virtualID,
                              message: DisplayControlText.text("無法保存復原設定，已取消切換", "Could not save recovery settings; switching cancelled"))
                return
            }
            secondsRemaining = 15
            BrightnessService.shared.refresh(force: true)
            if automaticConfirmation { confirm() }
            return
        }
        if !valid, attempts == 2, session.virtualID != nil {
            let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
            let modes = CGDisplayCopyAllDisplayModes(desktop, options) as? [CGDisplayMode] ?? []
            if let mode = modes.first(where: { Self.matches($0, profile: session.profile) }) {
                _ = CGDisplaySetDisplayMode(desktop, mode, nil)
            }
        }
        guard attempts < 30 else {
            abortCreation(id, original: session.original, virtual: session.virtualID,
                          message: DisplayControlText.text("HiDPI 模式或色彩描述檔未穩定，已恢復原設定", "HiDPI mode or color profile did not stabilize; restored original settings")); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.awaitVerification(id, token: token, attempts: attempts + 1)
        }
    }

    func confirm() {
        guard let id = confirmationDisplay, let session = sessions[id], watchdog?.isRunning == true,
              let url = journalURL,
              !FileManager.default.fileExists(atPath: url.appendingPathExtension("restored").path) else { return }
        journal?.confirmed = true
        do { if let journal { try journal.save(to: url) } }
        catch { stopAll(); failure = error.localizedDescription; return }
        confirmationDisplay = nil
        DisplayWindowMemoryService.shared.endManagedDisplayTransition()
        var saved = savedProfiles()
        saved[session.uuid] = session.profile
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: profilesKey) }
        scheduleSavedProfiles()
    }

    func disable(_ id: CGDirectDisplayID) {
        guard let session = sessions[id], switching == nil else { return }
        generation += 1
        DisplayWindowMemoryService.shared.beginManagedDisplayTransition()
        // Restore this physical display, preserving other active HiDPI sessions.
        let restored = session.original.restoringOnly(uuid: session.uuid)
        guard restored else {
            DisplayWindowMemoryService.shared.endManagedDisplayTransition()
            failure = "Display restore failed; recovery helper remains armed"; return
        }
        removeSession(id)
        confirmationDisplay = nil
        var saved = savedProfiles(); saved[session.uuid] = nil
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: profilesKey) }
        if sessions.isEmpty { finishRecovery() }
        else {
            journal?.confirmed = true
            if let journal, let url = journalURL { try? journal.save(to: url) }
        }
        DisplayWindowMemoryService.shared.endManagedDisplayTransition()
        BrightnessService.shared.refresh(force: true)
    }

    func stopAll() {
        resumeWork?.cancel(); resumeWork = nil
        generation += 1
        guard baseline != nil else { return }
        DisplayWindowMemoryService.shared.beginManagedDisplayTransition()
        let restored = baseline?.restore() == true
        for id in Array(sessions.keys) { removeSession(id) }
        switching = nil; confirmationDisplay = nil
        if restored { finishRecovery() }
        else {
            journal?.confirmed = false; journal?.deadline = Date().timeIntervalSince1970
            if let journal, let url = journalURL { try? journal.save(to: url) }
            failure = "Display restore pending in recovery helper"
        }
        DisplayWindowMemoryService.shared.endManagedDisplayTransition()
    }

    private func removeSession(_ id: CGDirectDisplayID) {
        if let virtual = sessions[id]?.virtualID {
            stopHost(id)
            _ = Self.ownershipLock.withLock { Self.physicalByVirtual.removeValue(forKey: virtual) }
        }
        stopHost(id)
        sessions[id] = nil
    }

    private func stopHost(_ id: CGDirectDisplayID) {
        if let host = hosts.removeValue(forKey: id), host.isRunning { host.terminate() }
        journal?.hostPIDs = hosts.values.map(\.processIdentifier)
        if let journal, let journalURL { try? journal.save(to: journalURL) }
        if let url = hostRequests.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("display"))
        }
    }

    private func abortCreation(_ id: CGDirectDisplayID, original: DisplayRecoverySnapshot,
                               virtual: CGDirectDisplayID?, message: String) {
        let restored = original.restoringOnly(uuid: DisplayRecoverySnapshot.uuid(id))
        if let virtual {
            stopHost(id)
            _ = Self.ownershipLock.withLock { Self.physicalByVirtual.removeValue(forKey: virtual) }
        }
        stopHost(id)
        sessions[id] = nil; switching = nil; confirmationDisplay = nil
        failure = message
        if restored && sessions.isEmpty { finishRecovery() }
        else if restored {
            journal?.confirmed = true
            if let journal, let url = journalURL { try? journal.save(to: url) }
        }
        DisplayWindowMemoryService.shared.endManagedDisplayTransition()
        BrightnessService.shared.refresh(force: true)
    }

    private func armRecovery(snapshot: DisplayRecoverySnapshot) throws {
        if baseline == nil {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DisplayRecoveryHelper")
            guard FileManager.default.isExecutableFile(atPath: helper.path) else {
                throw NSError(domain: "HiDPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Display recovery helper missing"])
            }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Vorssaint").appendingPathComponent("DisplayRecovery")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent(UUID().uuidString + ".json")
            let newJournal = DisplayRecoveryJournal(parentPID: getpid(), snapshot: snapshot,
                                                   deadline: Date().timeIntervalSince1970 + 40)
            try newJournal.save(to: url)
            let process = Process(); process.executableURL = helper; process.arguments = [url.path]
            try process.run()
            baseline = snapshot; journal = newJournal; journalURL = url; watchdog = process
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.checkRecovery() }
        } else {
            guard watchdog?.isRunning == true else { stopAll(); throw NSError(domain: "HiDPI", code: 2) }
            journal?.confirmed = false; journal?.deadline = Date().timeIntervalSince1970 + 40
            if let journal, let url = journalURL { try journal.save(to: url) }
        }
    }

    private func checkRecovery() {
        guard let url = journalURL else { return }
        if FileManager.default.fileExists(atPath: url.appendingPathExtension("restored").path) {
            let result = (try? String(contentsOf: url.appendingPathExtension("restored"))) ?? "failed"
            generation += 1
            for id in Array(sessions.keys) { removeSession(id) }
            switching = nil; confirmationDisplay = nil
            failure = result == "restored" ? DisplayControlText.text("已恢復原顯示設定", "Original display settings restored") : "Display recovery failed"
            if result == "restored" { finishRecovery() }
            else { timer?.invalidate(); timer = nil }
            DisplayWindowMemoryService.shared.endManagedDisplayTransition()
            BrightnessService.shared.refresh(force: true)
        } else if watchdog?.isRunning != true { stopAll(); failure = "Display recovery helper stopped" }
        else if confirmationDisplay != nil, let journal {
            secondsRemaining = max(0, Int(ceil(journal.deadline - Date().timeIntervalSince1970)))
        }
    }

    private func finishRecovery() {
        timer?.invalidate(); timer = nil
        if let url = journalURL {
            try? Data().write(to: url.appendingPathExtension("done"), options: .atomic)
            // Let the watchdog observe done before removing its files.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                for file in [url, url.appendingPathExtension("ready"), url.appendingPathExtension("done"), url.appendingPathExtension("restored")] {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        baseline = nil; journal = nil; journalURL = nil; watchdog = nil
    }

    private func savedProfiles() -> [String: Profile] {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let saved = try? JSONDecoder().decode([String: Profile].self, from: data) else { return [:] }
        return saved
    }

    private func topologyChanged() {
        guard switching == nil, confirmationDisplay == nil else { return }
        let online = Set(DisplayRecoverySnapshot.onlineIDs())
        let physicalUUIDs = Set(online.filter { !Self.isOwnedDisplay($0) }.compactMap(DisplayRecoverySnapshot.uuid))
        autoAttempted.formIntersection(physicalUUIDs)
        for (id, session) in sessions where !online.contains(id)
            || DisplayRecoverySnapshot.uuid(id) != session.uuid
            || (session.virtualID.map { !online.contains($0) } ?? false) {
            removeSession(id)
        }
        if sessions.isEmpty, baseline != nil { stopAll() }
        scheduleSavedProfiles()
    }

    func syncWithPreferences() {
        let wanted = AppFeature.brightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled)
        if wanted { scheduleSavedProfiles() }
        else { autoAttempted.removeAll(); stopAll() }
    }

    private func scheduleSavedProfiles() {
        // A fixed short settle from the first topology event avoids both the
        // old three-second pause and starvation from a notification burst.
        guard resumeWork == nil, !savedProfiles().isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.resumeWork = nil
            self.resumeSavedProfiles()
        }
        resumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func resumeSavedProfiles() {
        guard switching == nil, confirmationDisplay == nil,
              AppFeature.brightness.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled) else { return }
        let saved = savedProfiles()
        for id in DisplayRecoverySnapshot.onlineIDs() where CGDisplayIsBuiltin(id) == 0
            && !Self.isOwnedDisplay(id) && sessions[id] == nil {
            guard let uuid = DisplayRecoverySnapshot.uuid(id), let profile = saved[uuid],
                  !autoAttempted.contains(uuid) else { continue }
            autoAttempted.insert(uuid)
            // Only previously confirmed settings on the exact same physical UUID.
            enable(id, profile: profile, automaticallyConfirm: true)
            return
        }
    }
}
