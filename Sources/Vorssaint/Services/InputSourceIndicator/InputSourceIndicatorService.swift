// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Read-only overlay. TIS stays on the main thread; caret reads are serialized
/// off it, bounded by messaging timeouts and one in-flight sample.
final class InputSourceIndicatorService {
    static let shared = InputSourceIndicatorService()
    private let queue = DispatchQueue(label: "com.imstevelin.input-source-caret", qos: .utility)
    private var timer: Timer?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var observer: AXObserver?
    private var observedElement: AXUIElement?
    private var observedPID: pid_t?
    private var panel: NSPanel?
    private var label: NSTextField?
    private var generation: UInt = 0
    private var sampling = false
    private var refreshPending = false
    private var observationGeneration: UInt = 0
    private var running = false
    private var sourceName = ""
    private var screenLocked = false
    private var displaysSleeping = false
    private var screenUnavailable: Bool { screenLocked || displaysSleeping }

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        dispatchPrecondition(condition: .onQueue(.main))
        let wanted = AppFeature.inputSourceIndicator.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.inputSourceIndicatorEnabled)
            && AXIsProcessTrusted() && SessionActivity.shared.isActive
        guard wanted else { suspend(); return }
        guard !running else { refresh(); return }
        running = true
        screenLocked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        displaysSleeping = false
        let distributed = DistributedNotificationCenter.default()
        tokens.append((distributed, distributed.addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { [weak self] _ in self?.readSource(); self?.refresh() }))
        for (name, hidden) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            tokens.append((distributed, distributed.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in self?.setScreenUnavailable(hidden, lock: true) }))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, hidden) in [(NSWorkspace.screensDidSleepNotification, true),
                               (NSWorkspace.screensDidWakeNotification, false)] {
            tokens.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.setScreenUnavailable(hidden, lock: false) }))
        }
        tokens.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.generation &+= 1
            self.panel?.orderOut(nil)
            self.removeAXObserver()
            self.readSource()
            self.refresh()
        }))
        let center = NotificationCenter.default
        tokens.append((center, center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel?.orderOut(nil); self?.refresh() }))
        // AX notifications are primary. A modest fallback handles apps that omit
        // selection/scroll notifications, geometry changes and permission revocation.
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard AXIsProcessTrusted() else { self.suspend(); return }
            self.readSource()
            self.refresh()
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        readSource()
        refresh()
    }

    func suspend() {
        generation &+= 1
        running = false
        timer?.invalidate()
        timer = nil
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
        removeAXObserver()
        panel?.orderOut(nil)
        panel = nil
        label = nil
    }

    private func setScreenUnavailable(_ hidden: Bool, lock: Bool) {
        if lock { screenLocked = hidden } else { displaysSleeping = hidden }
        generation &+= 1
        if hidden { panel?.orderOut(nil) } else { refresh() }
    }

    private func readSource() {
        guard let reading = InputSourceSelection.currentReading() else {
            sourceName = ""
            panel?.orderOut(nil)
            return
        }
        // Use the actual source name: ZH alone cannot distinguish 注音 and 倉頡.
        sourceName = reading.name.isEmpty ? reading.code : reading.name
    }

    private func refresh() {
        guard running, !screenUnavailable else { return }
        if sampling { refreshPending = true; return }
        refreshPending = false
        guard !IsSecureEventInputEnabled(), SessionActivity.shared.isActive,
              let app = NSWorkspace.shared.frontmostApplication else {
            panel?.orderOut(nil)
            return
        }
        let pid = app.processIdentifier
        let ticket = generation
        sampling = true
        queue.async { [weak self] in
            let result = Self.caret(pid: pid)
            DispatchQueue.main.async {
                guard let self else { return }
                self.sampling = false
                defer {
                    if self.refreshPending { self.refresh() }
                }
                guard self.running, !self.screenUnavailable, self.generation == ticket,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      SessionActivity.shared.isActive, AXIsProcessTrusted(), !IsSecureEventInputEnabled()
                else { return }
                self.observe(pid: pid, element: result?.element)
                guard let result else { self.panel?.orderOut(nil); return }
                self.show(axCaret: result.rect)
            }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func caret(pid: pid_t) -> (element: AXUIElement, rect: CGRect)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        guard let focused = attribute(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.12)
        guard let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              (attribute(element, kAXSubroleAttribute) as? String) != "AXSecureTextField",
              let selection = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(selection) == AXValueGetTypeID() else { return nil }
        let value = selection as! AXValue
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range),
              range.location >= 0, range.length >= 0,
              range.location <= Int.max - range.length else { return nil }
        // A selection or marked composition still has an insertion endpoint.
        range.location += range.length
        range.length = 0
        guard let caretRange = AXValueCreate(.cfRange, &range) else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element,
                    kAXBoundsForRangeParameterizedAttribute as CFString, caretRange, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        let rectValue = bounds as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(rectValue) == .cgRect, AXValueGetValue(rectValue, .cgRect, &rect),
              InputSourceIndicatorSupport.caretIsValid(rect) else { return nil }
        return (element, rect)
    }

    private func removeAXObserver() {
        observationGeneration &+= 1
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedElement = nil
        observedPID = nil
    }

    private func observe(pid: pid_t, element: AXUIElement?) {
        if observedPID == pid, let old = observedElement, let element, CFEqual(old, element) { return }
        if observedPID == pid, observedElement == nil, element == nil { return }
        removeAXObserver()
        observedPID = pid
        observedElement = element
        let ticket = observationGeneration
        let context = Unmanaged.passUnretained(self).toOpaque()
        queue.async { [weak self] in
            var next: AXObserver?
            guard AXObserverCreate(pid, { _, _, _, context in
                guard let context else { return }
                let service = Unmanaged<InputSourceIndicatorService>.fromOpaque(context).takeUnretainedValue()
                service.generation &+= 1
                service.refresh()
            }, &next) == .success, let next else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.12)
            for name in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification,
                         kAXWindowMovedNotification, kAXWindowResizedNotification] {
                AXObserverAddNotification(next, app, name as CFString, context)
            }
            if let element {
                AXObserverAddNotification(next, element, kAXSelectedTextChangedNotification as CFString, context)
            }
            DispatchQueue.main.async {
                guard let self, self.running, self.observationGeneration == ticket else { return }
                self.observer = next
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
            }
        }
    }

    private func show(axCaret: CGRect) {
        guard !sourceName.isEmpty, let primary = NSScreen.screens.first else {
            panel?.orderOut(nil); return
        }
        let caret = InputSourceIndicatorSupport.appKitCaret(axCaret, primaryTop: primary.frame.maxY)
        guard let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.intersects(caret.insetBy(dx: -1, dy: 0))
        }) else { panel?.orderOut(nil); return }
        if panel == nil {
            let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .floating
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            let background = NSVisualEffectView()
            background.material = .hudWindow
            background.blendingMode = .behindWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = 9
            background.layer?.masksToBounds = true
            let text = NSTextField(labelWithString: "")
            text.font = .systemFont(ofSize: 11, weight: .semibold)
            text.textColor = .labelColor
            text.alignment = .center
            text.lineBreakMode = .byTruncatingTail
            background.addSubview(text)
            window.contentView = background
            panel = window
            label = text
        }
        guard let panel, let label else { return }
        label.stringValue = sourceName
        // NSTextField's intrinsic size can remain constrained by its previous
        // frame after a shorter source. Measure the untruncated string instead.
        let font = label.font ?? NSFont.systemFont(ofSize: 11, weight: .semibold)
        let width = min(240, max(32, ceil((sourceName as NSString).size(withAttributes: [.font: font]).width) + 20))
        let size = CGSize(width: width, height: 24)
        let frame = InputSourceIndicatorSupport.badgeFrame(caret: caret, size: size, visibleFrame: screen.visibleFrame)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        label.frame = CGRect(x: 8, y: 5, width: width - 16, height: 15)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
