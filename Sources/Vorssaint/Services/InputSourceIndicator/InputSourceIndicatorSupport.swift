// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// AX screen coordinates have their origin at the top left of the primary display.
/// Exact caret and explicitly separate field-edge anchors share this conversion.
enum InputSourceIndicatorSupport {
    static func badgeText(sourceID: String, name: String, code: String) -> String {
        let id = sourceID.lowercased()
        let text = name.lowercased()
        if id.contains("zhuyin") || id.contains("bopomofo") || text.contains("注音") { return "注" }
        if id.contains("cangjie") || text.contains("倉頡") || text.contains("仓颉") { return "倉" }
        if id.contains("sucheng") || text.contains("速成") { return "速" }
        if id.contains("pinyin") || text.contains("拼音") { return "拼" }
        if id.contains("wubi") || text.contains("五筆") || text.contains("五笔") { return "五" }
        switch code.uppercased() {
        case "EN": return "A"
        case "ZH": return "中"
        case "JA": return "あ"
        case "KO": return "한"
        default: return String((code.isEmpty ? name : code).prefix(1)).uppercased()
        }
    }

    static func fieldAnchor(_ rect: CGRect) -> CGRect? {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width >= 4, rect.height >= 4, rect.width <= 20000, rect.height <= 20000 else { return nil }
        return CGRect(x: rect.minX, y: rect.maxY, width: 0, height: 1)
    }

    static func caretIsValid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width >= 0 && rect.width <= 8
            && rect.height >= 4 && rect.height <= 120
    }

    static func appKitCaret(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Prefer below/right, flip above near the bottom, then keep inside the display.
    static func badgeFrame(caret: CGRect, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 6
        let x = min(max(caret.maxX + gap, visibleFrame.minX), visibleFrame.maxX - size.width)
        let below = caret.minY - gap - size.height
        let y = below >= visibleFrame.minY ? below : caret.maxY + gap
        return CGRect(x: max(visibleFrame.minX, x),
                      y: max(visibleFrame.minY, min(y, visibleFrame.maxY - size.height)),
                      width: size.width, height: size.height)
    }
}
