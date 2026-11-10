import AppKit
import ApplicationServices

// This standalone controller uses volatile preferences and no disk store. It
// controls only the uniquely identified fixture window with a seeded profile.
enum DefaultsKey {
    static let windowRememberSizes = "windowRememberSizes"
    static let windowRestoreDisplayLayout = "windowRestoreDisplayLayout"
    static let windowDisplayMemory = "windowDisplayMemory"
    static let windowDisplayMemorySalt = "windowDisplayMemorySalt"
}
enum AppFeature {
    struct Feature { let isAvailable = true }
    static let windowLayout = Feature()
}
final class SessionActivity {
    static let shared = SessionActivity()
    let isActive = true
    func onChange(_ action: @escaping (Bool) -> Void) {}
}
enum VirtualHiDPIService {
    static func physicalDisplay(for id: CGDirectDisplayID) -> CGDirectDisplayID { id }
}
enum PrivateFileStore {
    static let containerURL: URL? = nil
    static func createDirectory(at url: URL) -> Bool { false }
}
enum WindowServerSnapshot {
    static var fixturePID: pid_t = 0
    static var hiddenUntil: TimeInterval = 0
    static func onScreen() -> [[String: Any]] {
        let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        // Model the creation-notification / on-screen-snapshot race. AX and
        // AppKit remain real; only visibility of the fixture is delayed 250ms.
        return all.filter {
            ProcessInfo.processInfo.systemUptime >= hiddenUntil || ($0[kCGWindowOwnerPID as String] as? pid_t) != fixturePID
        }
    }
}
@main struct Controller {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard AXIsProcessTrusted(), let screen = NSScreen.main,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { exit(77) }
        let bounds = CGDisplayBounds(id)
        let key = CGDisplayIsBuiltin(id) != 0 ? "builtin" : "external:\(CGDisplayVendorNumber(id)):\(CGDisplayModelNumber(id)):\(CGDisplaySerialNumber(id))"
        let usable = DisplayWindowMemorySupport.usableBounds(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, displayBounds: bounds)
        let geometry = RememberedWindowGeometry(relativeFrame: CGRect(x: usable.minX-bounds.minX+40, y: usable.minY-bounds.minY+40, width: 400, height: 300), maximized: false)
        var stored = RememberedDisplay()
        stored.openingFrames = [CommandLine.arguments[2] + ":": geometry]
        let memory = DisplayWindowMemory(displays: [key: stored])
        UserDefaults.standard.setVolatileDomain([
            DefaultsKey.windowRememberSizes: true,
            DefaultsKey.windowRestoreDisplayLayout: false,
            DefaultsKey.windowDisplayMemorySalt: "native-fixture",
            DefaultsKey.windowDisplayMemory: try JSONEncoder().encode(memory)
        ], forName: UserDefaults.argumentDomain)
        DisplayWindowMemoryService.shared.fixtureStart(pid: pid_t(CommandLine.arguments[1])!, ready: URL(fileURLWithPath: CommandLine.arguments[3]))
        DispatchQueue.main.asyncAfter(deadline: .now()+8) { exit(2) }
        app.run()
    }
}
