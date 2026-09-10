import AppKit
import SwiftUI

@main enum CatsApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = CatsDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class CatsDelegate: NSObject, NSApplicationDelegate {
    private let model = AppState()
    private var desktop: DesktopPanels?
    private var dashboard: NSWindow?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        desktop = DesktopPanels(model: model)
        desktop?.show()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Cats"
        item.button?.target = self
        item.button?.action = #selector(toggleMenu)
        statusItem = item
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                model: model,
                showDesktop: { [weak self] in self?.desktop?.show() },
                showDashboard: { [weak self] in self?.showDashboard() }
            ))
    }

    @objc private func toggleMenu() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showDashboard() {
        if dashboard == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Cats"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DashboardView(model: model))
            window.center()
            dashboard = window
        }
        dashboard?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
