// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum DisplayHardwareControl: UInt8, CaseIterable, Hashable {
    case contrast = 0x12, volume = 0x62, mute = 0x8d
}

struct DisplayHardwareValue: Equatable {
    var current: UInt16
    var maximum: UInt16
    var confirmed = true
    var normalized: Double { maximum > 0 ? min(1, Double(current) / Double(maximum)) : 0 }
}

struct DisplayHardwareState: Equatable {
    let identity: String
    var values: [DisplayHardwareControl: DisplayHardwareValue] = [:]
    var pending = Set<DisplayHardwareControl>()
    var failure: String?
}

/// Local hardware bindings deliberately do not enter portable settings backups.
enum DisplayHardwarePreferences {
    static let audioBindings = "displayHardwareAudioBindingsLocalV1"
}

enum DisplayControlText {
    static func text(_ traditional: String, _ english: String) -> String {
        switch L10n.shared.language {
        case .zhTW, .zhHK: return traditional
        case .zhHans: return traditional.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? traditional
        default: return english
        }
    }
    static var contrast: String { text("對比", "Contrast") }
    static var volume: String { text("螢幕音量", "Monitor volume") }
    static var mute: String { text("靜音", "Mute") }
    static var keep: String { text("保留設定", "Keep settings") }
    static var restore: String { text("恢復原設定", "Restore settings") }
    static var custom: String { text("自訂介面大小", "Custom interface size") }
    static var apply: String { text("套用", "Apply") }
    static var preparing: String { text("正在切換顯示模式…", "Switching display mode…") }
    static var unsupported: String { text("此連接未提供可讀取的 DDC 控制", "No readable DDC controls on this connection") }
    static var failed: String { text("顯示器未確認變更，已重新讀取", "Monitor did not confirm the change; refreshed its value") }
    static var audio: String { text("音量鍵控制此螢幕的音訊輸出", "Audio output whose volume keys control this monitor") }
    static var none: String { text("自動配對（預設）", "Automatic (default)") }
    static var needsPermission: String { text("使用音量鍵需要輔助使用權限", "Volume keys require Accessibility permission") }
    static var unavailable: String { text("此系統無法建立虛擬 HiDPI 顯示器", "Virtual HiDPI is unavailable on this system") }
}
