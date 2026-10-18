// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum InputSourceIndicatorTests {
    static func run(_ suite: TestSuite) {
        let support = InputSourceIndicatorSupport.self
        for (id, name, code, expected) in [
            ("com.apple.inputmethod.TCIM.Zhuyin", "繁體注音", "ZH", "注"),
            ("com.apple.keylayout.ABC", "ABC", "EN", "A"),
            ("com.apple.inputmethod.TCIM.Cangjie", "倉頡", "ZH", "倉"),
            ("com.apple.inputmethod.SCIM.ITABC", "拼音", "ZH", "拼"),
            ("jp.ime", "日本語", "JA", "あ"),
            ("kr.ime", "한국어", "KO", "한"),
            ("other", "Fallback", "", "F")
        ] {
            suite.expect(support.badgeText(sourceID: id, name: name, code: code) == expected,
                         "input source \(id) gets its compact native-style mark")
        }
        suite.expect(support.fieldAnchor(CGRect(x: -500, y: 20, width: 300, height: 80))
                     == CGRect(x: -500, y: 100, width: 0, height: 1),
                     "apps without caret bounds anchor at the focused field edge")
        suite.expect(support.fieldAnchor(.zero) == nil
                     && support.fieldAnchor(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 20)) == nil,
                     "field fallback rejects missing and invalid geometry")
        suite.expect(support.caretIsValid(CGRect(x: -1200, y: 30, width: 0, height: 20)),
                     "zero-width caret on a left-hand display is valid")
        for rect in [CGRect.zero, CGRect(x: 0, y: 0, width: 500, height: 20),
                     CGRect(x: 0, y: 0, width: 1, height: 500),
                     CGRect(x: CGFloat.nan, y: 0, width: 1, height: 20)] {
            suite.expect(!support.caretIsValid(rect), "invalid and whole-editor bounds never become caret badges")
        }
        let caret = support.appKitCaret(CGRect(x: -500, y: 300, width: 1, height: 20), primaryTop: 1080)
        suite.expect(caret == CGRect(x: -500, y: 760, width: 1, height: 20),
                     "AX caret conversion preserves negative display coordinates")
        let display = CGRect(x: -1000, y: -200, width: 1000, height: 800)
        for caret in [CGRect(x: -10, y: -195, width: 1, height: 20),
                      CGRect(x: -990, y: 550, width: 1, height: 20)] {
            let badge = support.badgeFrame(caret: caret, size: CGSize(width: 100, height: 24), visibleFrame: display)
            suite.expect(display.contains(badge), "badge remains within the target screen's visible area")
            suite.expect(!badge.intersects(caret), "badge leaves the insertion caret uncovered")
        }
        suite.expect(!AppFeature.inputSourceIndicator.installedByDefault
                     && AppFeature.inputSourceIndicator.enabledKeys == [DefaultsKey.inputSourceIndicatorEnabled]
                     && AppFeature.inputSourceIndicator.permissions == [.accessibility],
                     "caret badge is opt-in and only requires Accessibility")
        suite.expect(AppFeature.inputSourceIndicator.settingsDestination == FeatureSettingsDestination(.inputSourceIndicator)
                     && FeatureVisibilitySupport.features(for: .inputSourceIndicator) == [.inputSourceIndicator],
                     "feature installation and settings share one gate")
    }
}
