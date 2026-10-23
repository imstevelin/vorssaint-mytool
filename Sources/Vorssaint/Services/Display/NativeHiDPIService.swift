// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Prepares real-display scaled modes. It never creates a virtual display.
final class NativeHiDPIService: ObservableObject {
    static let shared = NativeHiDPIService()
    @Published private(set) var busy = false
    @Published private(set) var message: String?

    func prepare(_ id: CGDirectDisplayID, profile: VirtualHiDPIService.Profile) {
        guard !busy, CGDisplayIsOnline(id) != 0, CGDisplayIsBuiltin(id) == 0,
              VirtualHiDPIService.shared.sessions[id] == nil,
              CGDisplayMirrorsDisplay(id) == 0 else {
            message = DisplayControlText.text("請先關閉 HiDPI 鏡像，再準備原生縮放。", "Turn off HiDPI mirroring before preparing native scaling.")
            return
        }
        let identity = NativeHiDPIOverride.Identity(vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id))
        guard identity.valid, NativeHiDPIOverride.Size(width: profile.width, height: profile.height).valid else {
            message = DisplayControlText.text("此顯示器識別或尺寸不支援原生縮放。", "Native scaling is unavailable for this display identity or size.")
            return
        }
        run(["--apply", String(identity.vendor), String(identity.product), String(profile.width), String(profile.height)],
            prompt: DisplayControlText.text("準備實體螢幕的原生 HiDPI 模式（會保存原設定；相同型號螢幕共用）。", "Prepare native HiDPI for this display model, preserving its original override."))
    }
    func restore(_ id: CGDirectDisplayID) {
        guard !busy, VirtualHiDPIService.shared.sessions[id] == nil,
              CGDisplayIsOnline(id) != 0, CGDisplayIsBuiltin(id) == 0,
              CGDisplayMirrorsDisplay(id) == 0 else { return }
        let identity = NativeHiDPIOverride.Identity(vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id))
        guard identity.valid else { return }
        run(["--restore", String(identity.vendor), String(identity.product)],
            prompt: DisplayControlText.text("還原這個螢幕型號原有的顯示設定。", "Restore this display model's original override."))
    }
    private func run(_ arguments: [String], prompt: String) {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/NativeHiDPIHelper")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            message = DisplayControlText.text("缺少原生 HiDPI 輔助程式，請重新安裝 App。", "Native HiDPI helper is missing; reinstall the app.")
            return
        }
        busy = true
        message = nil
        let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = ([helper.path] + arguments).map(quote).joined(separator: " ")
        AdminShell.run(command, prompt: prompt) { [weak self] ok in
            DispatchQueue.main.async {
                self?.busy = false
                self?.message = ok
                    ? DisplayControlText.text("設定已保存。請重新連接螢幕或重新啟動 macOS，再開啟原生 HiDPI。模式仍須實際驗證。", "Configuration saved. Reconnect the display or restart macOS, then enable native HiDPI. Mode availability still requires verification.")
                    : DisplayControlText.text("未完成設定：授權可能取消，或顯示覆寫被其他工具更動。既有設定不會被強制覆蓋。", "Configuration was not completed: authorization may have been cancelled or another tool changed the override. Existing changes are not forced over.")
            }
        }
    }
}
