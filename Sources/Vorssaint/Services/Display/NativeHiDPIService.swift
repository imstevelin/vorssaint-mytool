// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
#if canImport(DisplayRecoverySupport)
import DisplayRecoverySupport
#endif

/// One switch: use an available native mode, otherwise prepare it once and
/// resume the explicit request after reconnect/restart. Never creates a mirror.
final class NativeHiDPIService: ObservableObject {
    static let shared = NativeHiDPIService()
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var pendingDisplays: [CGDirectDisplayID: String] = [:]
    private var requests: [String: NativeHiDPIActivation] = [:]
    private let requestsKey = "nativeHiDPIActivationRequestsLocalV1"
    private var observers: [NSObjectProtocol] = []
    private var idleObserver: AnyCancellable?
    private var readiness: [String: VirtualHiDPIService.ReconnectGate] = [:]
    private var suspended = true

    private init() {
        if let data = UserDefaults.standard.data(forKey: requestsKey),
           let saved = try? JSONDecoder().decode([String: NativeHiDPIActivation].self, from: data) {
            requests = saved.filter { $0.key == $0.value.uuid && $0.value.valid }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.resumePending() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.resumePending() })
        let hidpi = VirtualHiDPIService.shared
        idleObserver = hidpi.$switching.combineLatest(hidpi.$confirmationDisplay)
            .receive(on: DispatchQueue.main).sink { [weak self] switching, confirmation in
                if switching == nil && confirmation == nil { self?.resumePending() }
            }
        DispatchQueue.main.async { [weak self] in self?.resumePending() }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(requests) { UserDefaults.standard.set(data, forKey: requestsKey) }
    }
    func syncWithPreferences() {
        suspended = false
        resumePending()
    }
    func suspend() {
        suspended = true
        if !AppFeature.brightness.isAvailable || !UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled) {
            requests.removeAll(); pendingDisplays.removeAll(); readiness.removeAll(); save()
        }
    }
    private func remove(_ uuid: String) {
        requests[uuid] = nil
        readiness[uuid] = nil
        pendingDisplays = pendingDisplays.filter { $0.value != uuid }
        save()
    }
    func cancel(_ id: CGDirectDisplayID) {
        if let uuid = pendingDisplays[id] { remove(uuid) }
        message = nil
    }
    func activate(_ id: CGDirectDisplayID, profile: VirtualHiDPIService.Profile,
                  preservePhysicalRate: Bool, panel: NativeHiDPIOverride.PanelSize? = nil,
                  useAvailableDefault: Bool = false) {
        let hidpi = VirtualHiDPIService.shared
        guard !busy, hidpi.switching == nil, hidpi.confirmationDisplay == nil,
              hidpi.sessions[id] == nil, CGDisplayIsBuiltin(id) == 0,
              CGDisplayIsOnline(id) != 0, CGDisplayIsInMirrorSet(id) == 0,
              let uuid = DisplayRecoverySnapshot.uuid(id) else { return }
        let rate = preservePhysicalRate
            ? VirtualHiDPIService.preferredRefreshRate(requested: profile.rate,
                physical: CGDisplayCopyDisplayMode(id)?.refreshRate, cached: nil) : profile.rate
        let request = NativeHiDPIActivation(uuid: uuid, vendor: CGDisplayVendorNumber(id),
            product: CGDisplayModelNumber(id), width: profile.width, height: profile.height, rate: rate,
            panel: panel, useAvailableDefault: useAvailableDefault)
        guard request.valid else {
            message = DisplayControlText.text("解析度、更新率或面板尺寸無效。", "Invalid resolution, refresh rate or panel dimensions.")
            return
        }
        suspended = false
        readiness[uuid] = nil
        requests[uuid] = request; pendingDisplays[id] = uuid; save()
        evaluate(request, id: id, allowPreparation: true)
    }
    private func resumePending(excluding visited: Set<String> = []) {
        guard !suspended, !requests.isEmpty else { return }
        let ids = DisplayRecoverySnapshot.onlineIDs()
        // Numeric display IDs can be reused for a different monitor.
        pendingDisplays = pendingDisplays.filter { id, uuid in
            ids.contains(id) && requests[uuid]?.matches(uuid: DisplayRecoverySnapshot.uuid(id),
                vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id)) == true
        }
        guard !busy,
              VirtualHiDPIService.shared.switching == nil,
              VirtualHiDPIService.shared.confirmationDisplay == nil else { return }
        guard AppFeature.brightness.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled) else {
            requests.removeAll(); pendingDisplays.removeAll(); readiness.removeAll(); save(); return
        }
        for request in requests.values where !visited.contains(request.uuid) {
            let matching = ids.filter { DisplayRecoverySnapshot.uuid($0) == request.uuid }
            guard matching.count == 1, let id = matching.first else { continue }
            pendingDisplays = pendingDisplays.filter { $0.value != request.uuid || $0.key == id }
            pendingDisplays[id] = request.uuid
            if VirtualHiDPIService.shared.sessions[id] != nil { remove(request.uuid); continue }
            // A restart or topology event never triggers another admin prompt.
            evaluate(request, id: id, allowPreparation: false, visited: visited)
            return
        }
    }
    private func evaluate(_ request: NativeHiDPIActivation, id: CGDirectDisplayID, allowPreparation: Bool,
                          visited: Set<String> = []) {
        guard !suspended, requests[request.uuid] == request, CGDisplayIsOnline(id) != 0,
              CGDisplayIsBuiltin(id) == 0, CGDisplayIsInMirrorSet(id) == 0,
              DisplayRecoverySnapshot.uuid(id) == request.uuid,
              CGDisplayVendorNumber(id) == request.vendor, CGDisplayModelNumber(id) == request.product else { return }
        busy = true
        message = DisplayControlText.text("正在檢查此螢幕的原生 HiDPI 模式…", "Checking native HiDPI modes for this display…")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let options = NativeDisplayModes.options(for: id)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard !self.suspended, self.requests[request.uuid] == request,
                      DisplayRecoverySnapshot.uuid(id) == request.uuid else {
                    self.resumePending(excluding: visited.union([request.uuid])); return
                }
                guard AppFeature.brightness.isAvailable,
                      UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled) else {
                    self.remove(request.uuid); self.message = nil; return
                }
                guard CGDisplayIsOnline(id) != 0, CGDisplayIsBuiltin(id) == 0,
                      CGDisplayIsInMirrorSet(id) == 0,
                      CGDisplayVendorNumber(id) == request.vendor, CGDisplayModelNumber(id) == request.product else {
                    self.waitingMessage(); return
                }
                let hidpi = VirtualHiDPIService.shared
                guard hidpi.switching == nil, hidpi.confirmationDisplay == nil, hidpi.sessions[id] == nil else { return }
                if request.useAvailableDefault == true,
                   let available = NativeDisplayModes.preferredOption(width: request.width, height: request.height,
                       rate: request.rate, options: options),
                   available.width != request.width || available.height != request.height {
                    var adjusted = request
                    adjusted.width = available.width; adjusted.height = available.height
                    adjusted.useAvailableDefault = false
                    self.requests[request.uuid] = adjusted; self.save()
                    self.evaluate(adjusted, id: id, allowPreparation: allowPreparation, visited: visited)
                    return
                }
                let available = options.contains { $0.width == request.width && $0.height == request.height
                    && abs($0.rate - request.rate) < 0.5 }
                switch request.next(modeAvailable: available) {
                case .enable:
                    var gate = self.readiness[request.uuid] ?? VirtualHiDPIService.ReconnectGate()
                    var sample: VirtualHiDPIService.ReconnectSignature?
                    if NSScreen.screens.contains(where: {
                        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
                    }), let mode = CGDisplayCopyDisplayMode(id), let color = DisplayColorProfile.data(for: id),
                       DisplayColorProfile.matches(color, display: id) {
                        sample = .init(id: id, mode: mode.ioDisplayModeID, width: mode.width,
                            height: mode.height, rate: mode.refreshRate, color: color)
                    }
                    let ready = gate.observe(sample)
                    self.readiness[request.uuid] = gate
                    guard ready else {
                        if gate.exhausted {
                            self.message = DisplayControlText.text("螢幕或色彩尚未穩定，請稍後關閉再開啟 HiDPI。", "Display or color is not stable yet. Toggle HiDPI off and on later.")
                            self.resumePending(excluding: visited.union([request.uuid]))
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                                guard let self, !self.busy, self.requests[request.uuid] == request else { return }
                                self.evaluate(request, id: id, allowPreparation: allowPreparation, visited: visited)
                            }
                        }
                        return
                    }
                    self.remove(request.uuid); self.message = nil
                    hidpi.enable(id, profile: .init(width: request.width, height: request.height,
                        rate: request.rate, nativeOnly: true))
                case .prepare where allowPreparation:
                    var arguments = ["--apply", String(request.vendor), String(request.product),
                                     String(request.width), String(request.height)]
                    if let panel = request.panel { arguments += [String(panel.width), String(panel.height)] }
                    self.run(arguments, prompt: DisplayControlText.text(
                        "開啟原生 HiDPI，需要為此螢幕型號設定縮放模式；會備份原設定。",
                        "Enable native HiDPI by configuring scaled modes for this display model, preserving the original settings.")) { ok in
                        guard self.requests[request.uuid] == request else { return }
                        if ok {
                            var prepared = request; prepared.prepared = true
                            self.requests[request.uuid] = prepared; self.save()
                            self.waitingMessage(); self.resumePending()
                        } else { self.remove(request.uuid); self.resumePending() }
                    }
                case .prepare:
                    self.message = DisplayControlText.text("上次設定未完成，請關閉再開啟 HiDPI 以重試授權。", "Previous setup was not completed. Toggle HiDPI off and on to retry authorization.")
                    self.resumePending(excluding: visited.union([request.uuid]))
                default:
                    self.waitingMessage()
                    self.resumePending(excluding: visited.union([request.uuid]))
                }
            }
        }
    }
    private func waitingMessage() {
        message = DisplayControlText.text(
            "已保存開啟要求，等待螢幕重新連接或重新啟動 macOS 載入模式；屆時會自動嘗試並顯示確認倒數。若系統仍未提供此組解析度／更新率，將保持原畫面。關閉開關可取消。",
            "Request saved. Reconnect the display or restart macOS to load modes; HiDPI will be retried with a confirmation countdown. If this resolution/rate remains unavailable, the current desktop is retained. Turn off the switch to cancel.")
    }
    func restore(_ id: CGDirectDisplayID) {
        guard !busy, VirtualHiDPIService.shared.sessions[id] == nil,
              CGDisplayIsOnline(id) != 0, CGDisplayIsBuiltin(id) == 0,
              CGDisplayIsInMirrorSet(id) == 0 else { return }
        cancel(id)
        let identity = NativeHiDPIOverride.Identity(vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id))
        guard identity.valid else { return }
        run(["--restore", String(identity.vendor), String(identity.product)],
            prompt: DisplayControlText.text("還原這個螢幕型號原有的顯示設定。", "Restore this display model's original override.")) { _ in }
    }
    private func run(_ arguments: [String], prompt: String, completion: @escaping (Bool) -> Void) {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/NativeHiDPIHelper")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            message = DisplayControlText.text("缺少原生 HiDPI 輔助程式，請重新安裝 App。", "Native HiDPI helper is missing; reinstall the app.")
            completion(false); return
        }
        busy = true; message = nil
        let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = ([helper.path] + arguments).map(quote).joined(separator: " ")
        AdminShell.run(command, prompt: prompt) { [weak self] ok in
            DispatchQueue.main.async {
                self?.busy = false
                self?.message = ok
                    ? DisplayControlText.text("設定已保存，等待系統載入更新。", "Configuration saved; waiting for macOS to load it.")
                    : DisplayControlText.text("未完成設定：授權可能取消，或設定已被其他工具更動。", "Setup was not completed: authorization may have been cancelled or another tool changed the configuration.")
                completion(ok)
            }
        }
    }
}
