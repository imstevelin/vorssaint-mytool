// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// AX screen coordinates have their origin at the top left of the primary display.
/// Never substitute a mouse pointer or the bounds of an entire editor for a caret.
enum InputSourceIndicatorSupport {
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
