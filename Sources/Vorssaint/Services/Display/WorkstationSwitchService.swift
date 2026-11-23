// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Carbon.HIToolbox

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
    private var deskflow: Process?
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

    static let deskflowDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Vorssaint Workstation", isDirectory: true)

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.brightness.isAvailable && defaults.bool(forKey: DefaultsKey.workstationEnabled)
            && defaults.bool(forKey: DefaultsKey.brightnessControlEnabled)
        let usesDeskflow = enabled && defaults.bool(forKey: DefaultsKey.workstationDeskflowEnabled)
        hotkey.onPress = { [weak self] in self?.switchToWindows() }
        shortcutAvailable = hotkey.sync(enabled: enabled && !usesDeskflow,
                                        shortcut: Self.shortcut, storageKey: DefaultsKey.workstationShortcut)
        if usesDeskflow { startDeskflow() } else { stopDeskflow() }
    }

    func stop() {
        generation &+= 1
        hotkey.unregister()
        stopDeskflow()
    }

    func openDeskflowDirectory() {
        do {
            try FileManager.default.createDirectory(at: Self.deskflowDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Self.deskflowDirectory)
        } catch {
            status = error.localizedDescription
        }
    }

    private func startDeskflow() {
        guard deskflow == nil else { return }
        let executable = URL(fileURLWithPath: "/Applications/Deskflow.app/Contents/MacOS/deskflow-core")
        let config = Self.deskflowDirectory.appendingPathComponent("Deskflow.conf")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.isReadableFile(atPath: config.path) else {
            status = DisplayControlText.text("請先安裝 Deskflow 並建立伺服器設定。", "Install Deskflow and prepare its server profile first.")
            return
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["server", "--settings", config.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self, self.deskflow === ended else { return }
                self.deskflow = nil
                self.status = DisplayControlText.text("Deskflow 伺服器已停止，請查看設定資料夾的日誌。",
                                                      "Deskflow stopped. Check the log in its profile folder.")
            }
        }
        do {
            try process.run()
            deskflow = process
            status = DisplayControlText.text("Deskflow 伺服器已啟動。輸入和顯示切換由 ⌃⌥⇧F9 控制。",
                                             "Deskflow server started. Use Control–Option–Shift–F9 to switch input and video.")
        } catch {
            status = error.localizedDescription
        }
    }

    private func stopDeskflow() {
        let process = deskflow
        deskflow = nil
        if let process, process.isRunning { process.terminate() }
    }

    func diagnose() {
        guard !busy else { return }
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
        guard !busy, deskflow == nil, AppFeature.brightness.isAvailable, let settings else { return }
        guard let monitor else { showMissingMonitor(); return }
        busy = true
        writeInput(monitor, from: settings.mac.code, to: settings.windows.code, epoch: generation)
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
        status = DisplayControlText.text("已送出切換到 Windows 的指令。", "Sent the command to switch to Windows.")
    }

    private func showMissingMonitor() {
        status = DisplayControlText.text("讀不到 PA328QV 的 DDC/CI，請檢查顯示控制和影像連線。", "Cannot read DDC/CI from the PA328QV. Check display control and the video connection.")
    }

}
