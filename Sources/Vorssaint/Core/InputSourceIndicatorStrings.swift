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
                        caption: "以小型藍色圓標持續顯示目前輸入法，例如「注」或「A」。跟隨文字游標，切換後更新，不攔截點按或輸入。",
                        compatibility: "需要輔助使用權限。優先跟隨文字游標；App 只提供文字欄位範圍時，顯示在欄位下緣。離開文字欄位、密碼欄位或鎖定螢幕時隱藏。完全未提供文字焦點的 App 仍可能無法顯示。顯示的是系統輸入來源；輸入法內部未公開的中／英文模式無法判定。")
        case .zhHans:
            return Self(title: "光标输入法提示", enabled: "持续显示当前输入法",
                        caption: "以小型蓝色圆标持续显示当前输入法，例如「注」或「A」。跟随文字光标，切换后更新，不拦截点击或输入。",
                        compatibility: "需要辅助功能权限。优先跟随文字光标；App 只提供文本框范围时，显示在文本框下缘。离开文本框、密码框或锁定屏幕时隐藏。完全未提供文字焦点的 App 仍可能无法显示。显示的是系统输入来源；输入法内部未公开的中／英文模式无法判定。")
        default:
            return Self(title: "Caret input source", enabled: "Always show the current input source",
                        caption: "Keep a small blue input-source mark, such as 注 or A, beside the caret. It updates on switching and lets clicks and typing pass through.",
                        compatibility: "Requires Accessibility. Follows the text caret, or the lower edge of a text field when only field bounds are available. Hidden outside text fields, in password fields and when locked. Apps exposing no text focus may remain unsupported. Private internal IME language modes cannot be detected.")
        }
    }
}
