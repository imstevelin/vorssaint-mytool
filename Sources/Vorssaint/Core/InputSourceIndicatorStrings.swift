// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct InputSourceIndicatorStrings {
    let title: String
    let enabled: String
    let caption: String
    let compatibility: String

    static func text(_ language: AppLanguage) -> Self {
        switch language {
        case .zhTW, .zhHK:
            return Self(title: "游標輸入法提示", enabled: "持續顯示目前輸入法",
                        caption: "在文字插入游標旁顯示系統目前的輸入法，切換後立即更新。提示不會自動消失，也不會攔截點按或鍵盤輸入。",
                        compatibility: "需要輔助使用權限。只有 App 提供可靠的文字游標位置時才顯示；離開文字欄位、密碼欄位或鎖定螢幕時隱藏。部分瀏覽器、自繪編輯器與終端機可能不支援。顯示的是系統輸入來源；輸入法內部未公開的中／英文模式無法判定。")
        case .zhHans:
            return Self(title: "光标输入法提示", enabled: "持续显示当前输入法",
                        caption: "在文字插入光标旁显示系统当前的输入法，切换后立即更新。提示不会自动消失，也不会拦截点击或键盘输入。",
                        compatibility: "需要辅助功能权限。只有 App 提供可靠的文字光标位置时才显示；离开文本框、密码框或锁定屏幕时隐藏。部分浏览器、自绘编辑器与终端可能不支持。显示的是系统输入来源；输入法内部未公开的中／英文模式无法判定。")
        default:
            return Self(title: "Caret input source", enabled: "Always show the current input source",
                        caption: "Keep the system input source beside the text caret and update it when switching. The badge stays visible and lets clicks and typing pass through.",
                        compatibility: "Requires Accessibility. Shown only when the app exposes a reliable text caret; hidden outside text fields, in password fields and when locked. Some browsers, custom editors and terminals may not support it. Private internal IME language modes cannot be detected.")
        }
    }
}
