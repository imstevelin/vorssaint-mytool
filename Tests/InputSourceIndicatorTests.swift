// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum InputSourceIndicatorTests {
    static func run(_ suite: TestSuite) {
        let support = InputSourceIndicatorSupport.self
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
