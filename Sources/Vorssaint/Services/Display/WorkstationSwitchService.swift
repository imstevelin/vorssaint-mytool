// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Carbon.HIToolbox
import IOBluetooth

enum WorkstationInputResult {
    case current(UInt16)
    case sent
    case unavailable
}

enum WorkstationPort: Int, CaseIterable, Identifiable {
    case hdmi1 = 17, hdmi2 = 18, displayPort = 15

    var id: Int { rawValue }
    var code: UInt16 { UInt16(rawValue) }
    var label: String {
        switch self {
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .displayPort: return "DisplayPort"
        }
    }
}

final class WorkstationSwitchService: ObservableObject {
    static let shared = WorkstationSwitchService()
    private static let shortcut = GlobalShortcut(keyCode: Int64(kVK_F9), modifiers: [.control, .option, .shift])
    private let hotkey = QuickToolHotkey(id: 82)
    private let bluetoothQueue = DispatchQueue(label: "workstation.bluetooth", qos: .userInitiated)
    private var timer: Timer?
    private var polling = false
    private var switchAfterPoll = false
    private var lastInput: UInt16?
    private var generation = 0
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    @Published private(set) var shortcutAvailable = true

    private var settings: (mac: WorkstationPort, windows: WorkstationPort)? {
        let defaults = UserDefaults.standard
        let mac = defaults.object(forKey: DefaultsKey.workstationMacInput) as? Int ?? WorkstationPort.hdmi1.rawValue
        let windows = defaults.object(forKey: DefaultsKey.workstationWindowsInput) as? Int ?? WorkstationPort.hdmi2.rawValue
        guard let mac = WorkstationPort(rawValue: mac), let windows = WorkstationPort(rawValue: windows), mac != windows else { return nil }
        return (mac, windows)
    }

    private var monitor: CGDirectDisplayID? {
        // Match the actual panel in the existing display snapshot. Ambiguous
        // setups must not write VCP commands to an arbitrary monitor.
        let candidates = BrightnessService.shared.displays.filter {
            !$0.isBuiltIn && $0.isActive && CGDisplayVendorNumber($0.id) == 0x06b3
                && CGDisplayModelNumber($0.id) == 0x32c2
        }
        return candidates.count == 1 ? candidates[0].id : nil
    }

    private var followsBluetooth: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.workstationBluetoothEnabled)
    }

    func syncWithPreferences() {
        generation &+= 1
        lastInput = nil
        switchAfterPoll = false
        timer?.invalidate()
        timer = nil
        let defaults = UserDefaults.standard
        let enabled = AppFeature.brightness.isAvailable && defaults.bool(forKey: DefaultsKey.workstationEnabled)
            && defaults.bool(forKey: DefaultsKey.brightnessControlEnabled)
        hotkey.onPress = { [weak self] in self?.switchToWindows() }
        shortcutAvailable = hotkey.sync(enabled: enabled, shortcut: Self.shortcut, storageKey: DefaultsKey.workstationShortcut)
        if enabled, followsBluetooth {
            let poll = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.pollInput() }
            poll.tolerance = 0.4
            RunLoop.main.add(poll, forMode: .common)
            timer = poll
        }
    }

    func stop() {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        hotkey.unregister()
    }

    func diagnose() {
        guard !busy, !polling else { return }
        guard let monitor else { showMissingMonitor(); return }
        busy = true
        BrightnessService.shared.workstationInput(for: monitor) { result in
            self.busy = false
            if case let .current(code) = result {
                let port = WorkstationPort(rawValue: Int(code))?.label ?? String(format: "0x%02X", code)
                self.status = DisplayControlText.text("目前來源為 \(port)。", "Current input is \(port).")
            } else { self.showMissingMonitor() }
        }
    }

    func switchToWindows() {
        guard !busy, AppFeature.brightness.isAvailable, let settings else { return }
        if polling { switchAfterPoll = true; return }
        guard let monitor else { showMissingMonitor(); return }
        busy = true
        let epoch = generation
        if followsBluetooth {
            bluetoothQueue.async {
                let ready = Self.pairedAccessories() != nil
                DispatchQueue.main.async {
                    guard ready, self.generation == epoch else {
                        self.busy = false
                        if !ready { self.showMissingPair() }
                        return
                    }
                    self.writeInput(monitor, from: settings.mac.code, to: settings.windows.code, epoch: epoch)
                }
            }
        } else {
            writeInput(monitor, from: settings.mac.code, to: settings.windows.code, epoch: epoch)
        }
    }

    private func writeInput(_ monitor: CGDirectDisplayID, from source: UInt16, to target: UInt16, epoch: Int) {
        BrightnessService.shared.workstationInput(for: monitor, from: source, to: target) { result in
            guard self.generation == epoch else { self.busy = false; return }
            switch result {
            case .sent:
                // Let the current DDC connection settle before checking its
                // reported input. Losing the source after a write is expected.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    guard self.generation == epoch else { self.busy = false; return }
                    BrightnessService.shared.workstationInput(for: monitor) { confirmation in
                        self.finishSwitch(confirmation, target: target, epoch: epoch)
                    }
                }
            case .current(let code) where code == target:
                self.finishSwitch(result, target: target, epoch: epoch)
            default:
                self.busy = false
                self.status = DisplayControlText.text("切換失敗，請檢查目前接孔與 DDC/CI。", "Switch failed. Check the current input and DDC/CI.")
            }
        }
    }

    private func finishSwitch(_ result: WorkstationInputResult, target: UInt16, epoch: Int) {
        busy = false
        guard generation == epoch else { return }
        if case let .current(code) = result, code != target {
            status = DisplayControlText.text("螢幕尚未切到 Windows。", "The monitor has not switched to Windows.")
            return
        }
        lastInput = target
        status = DisplayControlText.text("已送出切換到 Windows 的指令。", "Sent the command to switch to Windows.")
        if followsBluetooth { updateBluetooth(connected: false, epoch: epoch) }
    }

    private func pollInput() {
        guard !busy, !polling, AppFeature.brightness.isAvailable, followsBluetooth, let settings, let monitor else { return }
        let epoch = generation
        polling = true
        BrightnessService.shared.workstationInput(for: monitor) { result in
            self.polling = false
            guard self.generation == epoch else { return }
            if self.switchAfterPoll {
                self.switchAfterPoll = false
                self.switchToWindows()
                return
            }
            guard case let .current(current) = result, self.lastInput != current else { return }
            let previous = self.lastInput
            self.lastInput = current
            if current == settings.mac.code { self.updateBluetooth(connected: true, epoch: epoch) }
            else if current == settings.windows.code, previous == settings.mac.code {
                self.updateBluetooth(connected: false, epoch: epoch)
            }
        }
    }

    private func updateBluetooth(connected: Bool, epoch: Int) {
        busy = true
        bluetoothQueue.async {
            guard let devices = Self.pairedAccessories() else {
                DispatchQueue.main.async {
                    self.busy = false
                    if self.generation == epoch { self.showMissingPair() }
                }
                return
            }
            if connected {
                for _ in 0..<3 {
                    for device in devices where !device.isConnected() {
                        _ = device.openConnection(nil, withPageTimeout: 0x1400, authenticationRequired: true)
                    }
                    if devices.allSatisfy({ $0.isConnected() }) { break }
                    Thread.sleep(forTimeInterval: 0.4)
                }
            } else {
                // Trackpad first keeps the keyboard available on partial failure.
                for device in devices.reversed() where device.isConnected() {
                    _ = device.closeConnection()
                    if device.isConnected() { break }
                }
            }
            let complete = devices.allSatisfy { $0.isConnected() == connected }
            DispatchQueue.main.async {
                self.busy = false
                guard self.generation == epoch else { return }
                if complete {
                    self.status = connected
                        ? DisplayControlText.text("鍵盤與觸控板已連到 Mac。", "Keyboard and trackpad are connected to this Mac.")
                        : DisplayControlText.text("已從 Mac 釋放鍵盤與觸控板。", "Released the keyboard and trackpad from this Mac.")
                } else {
                    self.status = DisplayControlText.text("藍牙交接未完成，請檢查配件狀態。", "Bluetooth handoff is incomplete. Check the accessories.")
                }
            }
        }
    }

    private static func pairedAccessories() -> [IOBluetoothDevice]? {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isPaired() }
        let keyboard = paired.filter { $0.name?.localizedCaseInsensitiveContains("Magic Keyboard") == true }
        let trackpad = paired.filter { $0.name?.localizedCaseInsensitiveContains("Magic Trackpad") == true }
        guard keyboard.count == 1, trackpad.count == 1, keyboard[0].addressString != trackpad[0].addressString else { return nil }
        return [keyboard[0], trackpad[0]]
    }

    private func showMissingMonitor() {
        status = DisplayControlText.text("讀不到 PA328QV 的 DDC/CI，請檢查顯示控制和影像連線。", "Cannot read DDC/CI from the PA328QV. Check display control and the video connection.")
    }

    private func showMissingPair() {
        status = DisplayControlText.text("請先在 Mac 配對一組 Magic Keyboard 與 Magic Trackpad。", "Pair one Magic Keyboard and one Magic Trackpad with this Mac first.")
    }
}
