// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices

/// Queue-confined AX adapter. Never reads a text value or selected text.
final class InputSourceCaretReader {
    struct Position {
        let element: AXUIElement
        let rect: CGRect
    }
    private var attempted: [pid_t: NSRunningApplication] = [:]
    private var activated: [pid_t: (app: NSRunningApplication, element: AXUIElement)] = [:]

    /// Electron documents this assistive-client signal. Preserve an existing
    /// true value and restore only false values this feature itself changed.
    /// AXEnhancedUserInterface is deliberately left alone: it affects resizing.
    private func prepare(_ application: NSRunningApplication, element: AXUIElement) {
        let pid = application.processIdentifier
        if let previous = attempted[pid], !previous.isTerminated { return }
        attempted[pid] = application
        AXUIElementSetMessagingTimeout(element, 0.12)
        var value: CFTypeRef?
        let name = "AXManualAccessibility" as CFString
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success,
              (value as? Bool) == false else { return }
        _ = AXUIElementSetAttributeValue(element, name, kCFBooleanTrue)
        value = nil
        if AXUIElementCopyAttributeValue(element, name, &value) == .success, (value as? Bool) == true {
            activated[pid] = (application, element)
        }
    }

    func reset() {
        for (_, entry) in activated where !entry.app.isTerminated {
            AXUIElementSetMessagingTimeout(entry.element, 0.12)
            _ = AXUIElementSetAttributeValue(entry.element, "AXManualAccessibility" as CFString, kCFBooleanFalse)
        }
        activated.removeAll()
        attempted.removeAll()
    }

    func read(application: NSRunningApplication) -> Position? {
        let app = AXUIElementCreateApplication(application.processIdentifier)
        prepare(application, element: app)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        guard let raw = value(app, kAXFocusedUIElementAttribute, deadline: deadline),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let focused = raw as! AXUIElement
        guard !CFEqual(focused, app), !protected(focused, deadline: deadline) else { return nil }

        // Native AppKit ranges, then WebKit/Chromium text-marker ranges. Do not
        // gate these on AXRole: contenteditable frequently focuses a group/page.
        if let rect = rangeCaret(focused, deadline: deadline) {
            return Position(element: focused, rect: rect)
        }
        var candidate = focused
        for _ in 0..<5 {
            guard !protected(candidate, deadline: deadline) else { return nil }
            if let marker = value(candidate, "AXSelectedTextMarkerRange", deadline: deadline),
               CFGetTypeID(marker) == AXTextMarkerRangeGetTypeID() {
                let range = marker as! AXTextMarkerRange
                let end = AXTextMarkerRangeCopyEndMarker(range)
                let collapsed = AXTextMarkerRangeCreate(kCFAllocatorDefault, end, end)
                if let rect = rect(candidate, "AXBoundsForTextMarkerRange", parameter: collapsed, deadline: deadline),
                   InputSourceIndicatorSupport.caretIsValid(rect) {
                    return Position(element: focused, rect: rect)
                }
            }
            guard let parent = value(candidate, kAXParentAttribute, deadline: deadline),
                  CFGetTypeID(parent) == AXUIElementGetTypeID(), !CFEqual(parent, candidate), !CFEqual(parent, app)
            else { break }
            candidate = parent as! AXUIElement
        }

        // A field that exposes no caret still gets a persistent marker at its
        // lower edge. This is explicitly a field anchor, never a mouse guess.
        guard let role = value(focused, kAXRoleAttribute, deadline: deadline) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
                || (value(focused, "AXEditable", deadline: deadline) as? Bool) == true,
              (value(focused, kAXEnabledAttribute, deadline: deadline) as? Bool) != false,
              let origin = value(focused, kAXPositionAttribute, deadline: deadline),
              let size = value(focused, kAXSizeAttribute, deadline: deadline),
              CFGetTypeID(origin) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        let positionValue = origin as! AXValue
        let sizeValue = size as! AXValue
        guard AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &dimensions),
              let anchor = InputSourceIndicatorSupport.fieldAnchor(CGRect(origin: point, size: dimensions))
        else { return nil }
        return Position(element: focused, rect: anchor)
    }

    private func protected(_ element: AXUIElement, deadline: TimeInterval) -> Bool {
        (value(element, kAXSubroleAttribute, deadline: deadline) as? String) == "AXSecureTextField"
            || (value(element, "AXProtectedContent", deadline: deadline) as? Bool) == true
    }

    private func rangeCaret(_ element: AXUIElement, deadline: TimeInterval) -> CGRect? {
        guard let raw = value(element, kAXSelectedTextRangeAttribute, deadline: deadline),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let selection = raw as! AXValue
        var range = CFRange()
        guard AXValueGetType(selection) == .cfRange, AXValueGetValue(selection, .cfRange, &range),
              range.location >= 0, range.length >= 0, range.location <= Int.max - range.length else { return nil }
        range.location += range.length
        range.length = 0
        guard let parameter = AXValueCreate(.cfRange, &range),
              let rect = rect(element, kAXBoundsForRangeParameterizedAttribute, parameter: parameter, deadline: deadline),
              InputSourceIndicatorSupport.caretIsValid(rect) else { return nil }
        return rect
    }

    private func value(_ element: AXUIElement, _ name: String,
                       parameter: CFTypeRef? = nil, deadline: TimeInterval) -> CFTypeRef? {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return nil }
        AXUIElementSetMessagingTimeout(element, Float(min(0.12, remaining)))
        var result: CFTypeRef?
        let error = parameter.map {
            AXUIElementCopyParameterizedAttributeValue(element, name as CFString, $0, &result)
        } ?? AXUIElementCopyAttributeValue(element, name as CFString, &result)
        return error == .success ? result : nil
    }

    private func rect(_ element: AXUIElement, _ name: String,
                      parameter: CFTypeRef, deadline: TimeInterval) -> CGRect? {
        guard let raw = value(element, name, parameter: parameter, deadline: deadline),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        var result = CGRect.zero
        guard AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &result) else { return nil }
        return result
    }
}
