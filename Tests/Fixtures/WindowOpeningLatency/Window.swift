import AppKit
@main struct WindowFixture {
    static var window: NSWindow?
    static var started: TimeInterval = 0
    static var resizeObserver: NSObjectProtocol?
    static let deadline = ProcessInfo.processInfo.systemUptime + 8
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        waitForController()
        app.run()
    }
    static func waitForController() {
        guard ProcessInfo.processInfo.systemUptime < deadline else { exit(2) }
        if FileManager.default.fileExists(atPath: CommandLine.arguments[1]) {
            window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window?.isReleasedWhenClosed = false
            window?.title = "Window opening latency fixture"
            resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                object: window, queue: .main) { _ in checkPlacement() }
            started = ProcessInfo.processInfo.systemUptime
            window?.orderFront(nil)
            checkPlacement()
            DispatchQueue.main.asyncAfter(deadline: .now()+3) { print("fixture placement timed out"); exit(2) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now()+0.01, execute: waitForController)
        }
    }
    static func checkPlacement() {
        let elapsed = ProcessInfo.processInfo.systemUptime-started
        if let frame = window?.frame, abs(frame.width-400)<2, abs(frame.height-300)<2 {
            print("{\"placement_ms\":\(elapsed*1000)}")
            window?.close()
            exit(0)
        }
        // Completion follows the actual native resize event, not a sampling timer.
    }
}
