// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import Darwin
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
    private var deskflowOutput: Pipe?
    private var restartDeskflow = false
    private var generation = 0
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    @Published private(set) var shortcutAvailable = true
    @Published private(set) var localFingerprint = ""
    @Published private(set) var pairedFingerprint = ""
    @Published private(set) var pairingBusy = false
    @Published private(set) var clientConnected = false

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

    private static let pinnedClient = deskflowDirectory.appendingPathComponent("tls/trusted-clients")

    var lanAddress: String {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return ProcessInfo.processInfo.hostName }
        defer { freeifaddrs(first) }
        var values: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  entry.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let hostLength = socklen_t(host.count)
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, hostLength, nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: host)
                if String(cString: entry.ifa_name).hasPrefix("en") { return value }
                values.append(value)
            }
        }
        return values.first ?? ProcessInfo.processInfo.hostName
    }

    func loadPairing() { updatePairing(nil) }

    func savePairing(_ fingerprint: String, completion: @escaping () -> Void) {
        let pin = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ":", with: "").lowercased()
        guard pin.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            status = DisplayControlText.text("請輸入 64 位十六進位 Windows 指紋。", "Enter the 64-character Windows SHA-256 fingerprint.")
            return
        }
        updatePairing(pin, completion: completion)
    }

    func forgetPairing() {
        guard !pairingBusy else { return }
        do {
            if FileManager.default.fileExists(atPath: Self.pinnedClient.path) {
                try FileManager.default.removeItem(at: Self.pinnedClient)
            }
            stopDeskflow()
            pairedFingerprint = ""
            UserDefaults.standard.set(false, forKey: DefaultsKey.workstationDeskflowEnabled)
            syncWithPreferences()
            status = DisplayControlText.text("已移除 Windows 配對。Mac 自己的指紋保持有效。", "Windows pairing removed. The Mac fingerprint is unchanged.")
        } catch { status = error.localizedDescription }
    }

    private func updatePairing(_ fingerprint: String?, completion: (() -> Void)? = nil) {
        guard !pairingBusy else { return }
        guard let script = Bundle.main.url(forResource: "setup-workstation-deskflow", withExtension: "sh") else {
            status = DisplayControlText.text("找不到內建配對工具。", "The pairing tool is missing from this build.")
            return
        }
        pairingBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<(String, String), Error>
            do {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [script.path] + (fingerprint.map { [$0] } ?? [])
                process.standardOutput = output
                process.standardError = output
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard process.terminationStatus == 0, message.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                    throw NSError(domain: "DeskflowPairing", code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Deskflow pairing failed." : message])
                }
                let pinned = (try? String(contentsOf: Self.pinnedClient, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                result = .success((message, pinned.hasPrefix("v2:sha256:") ? String(pinned.dropFirst(10)) : ""))
            } catch { result = .failure(error) }
            DispatchQueue.main.async {
                self.pairingBusy = false
                switch result {
                case let .success((local, peer)):
                    self.localFingerprint = local
                    self.pairedFingerprint = peer
                    if fingerprint != nil {
                        self.stopDeskflow()
                        self.restartDeskflow = self.deskflow != nil
                        completion?()
                        self.syncWithPreferences()
                    }
                case let .failure(error): self.status = error.localizedDescription
                }
            }
        }
    }

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

    private func migrateDeskflowShortcut() throws {
        let layout = Self.deskflowDirectory.appendingPathComponent("workstation.conf")
        let original = try String(contentsOf: layout, encoding: .utf8)
        // Deskflow's macOS hotkey registration maps Super to Option and Alt to Command.
        let updated = original.replacingOccurrences(
            of: "keystroke(Control+Alt+Shift+F9) = switchToNextScreen",
            with: "keystroke(Control+Super+Shift+F9) = switchToNextScreen"
        )
        if updated != original { try updated.write(to: layout, atomically: true, encoding: .utf8) }
    }

    private func startDeskflow() {
        guard deskflow == nil else { return }
        guard AXIsProcessTrusted() else {
            status = DisplayControlText.text("請先允許實用小工具使用輔助使用。", "Allow this app in macOS Accessibility before starting Deskflow.")
            return
        }
        let executable = URL(fileURLWithPath: "/Applications/Deskflow.app/Contents/MacOS/deskflow-core")
        let config = Self.deskflowDirectory.appendingPathComponent("Deskflow.conf")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.isReadableFile(atPath: config.path),
              FileManager.default.isReadableFile(atPath: Self.pinnedClient.path) else {
            status = DisplayControlText.text("請先安裝 Deskflow 並建立伺服器設定。", "Install Deskflow and prepare its server profile first.")
            return
        }
        do { try migrateDeskflowShortcut() }
        catch {
            status = DisplayControlText.text("無法讀取或更新 Deskflow 快捷鍵設定。", "Could not read or update the Deskflow shortcut.") + " " + error.localizedDescription
            return
        }
        let process = Process()
        let output = Pipe()
        let reader = FileHandleLogReader { [weak self, weak process] line in
            if line.contains("accepted client connection") || line.contains("disconnecting client") || line.contains("forced disconnection of client") {
                DispatchQueue.main.async {
                    guard let self, let process, self.deskflow === process else { return }
                    self.clientConnected = line.contains("accepted client connection")
                }
            }
            if line.contains("failed to register hotkey") {
                DispatchQueue.main.async {
                    guard let self, let process, self.deskflow === process else { return }
                    self.status = DisplayControlText.text("Deskflow 無法註冊快捷鍵。請檢查是否有其他程式使用同一組按鍵。",
                                                          "Deskflow could not register the shortcut. Check whether another app uses it.")
                }
            }
        }
        process.executableURL = executable
        process.arguments = ["server", "--settings", config.path]
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { handle in reader.consume(handle.availableData) }
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self, self.deskflow === ended else { return }
                self.deskflow = nil
                self.deskflowOutput?.fileHandleForReading.readabilityHandler = nil
                self.deskflowOutput = nil
                self.clientConnected = false
                if self.restartDeskflow {
                    self.restartDeskflow = false
                    self.syncWithPreferences()
                    return
                }
                self.status = DisplayControlText.text("Deskflow 伺服器已停止，請查看設定資料夾的日誌。",
                                                      "Deskflow stopped. Check the log in its profile folder.")
            }
        }
        do {
            try process.run()
            deskflow = process
            deskflowOutput = output
            status = DisplayControlText.text("Deskflow 伺服器已啟動。輸入和顯示切換由 ⌃⌥⇧F9 控制。",
                                             "Deskflow server started. Use Control–Option–Shift–F9 to switch input and video.")
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            status = error.localizedDescription
        }
    }

    private func stopDeskflow() {
        restartDeskflow = false
        clientConnected = false
        if let process = deskflow, process.isRunning { process.terminate() }
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

private final class FileHandleLogReader {
    private var pending = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func consume(_ bytes: Data) {
        pending.append(bytes)
        while let newline = pending.firstIndex(of: 10) {
            onLine(String(decoding: pending[..<newline], as: UTF8.self))
            pending.removeSubrange(...newline)
        }
        if pending.count > 65_536 { pending.removeAll(keepingCapacity: false) }
    }
}
