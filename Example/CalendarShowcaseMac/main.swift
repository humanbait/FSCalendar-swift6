import AppKit
import CalendarDemoSupportMac
import FSCalendarAppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "FSCalendar — AppKit"
        window.identifier = NSUserInterfaceItemIdentifier("showcase.window")
        window.contentViewController = ShowcaseController()
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
let menu = NSMenu(); let appMenu = NSMenuItem(); menu.addItem(appMenu)
appMenu.submenu = NSMenu(); appMenu.submenu?.addItem(withTitle: "Quit Calendar Showcase", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
application.mainMenu = menu
application.run()
