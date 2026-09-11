import AppKit
import SwiftUI

@main enum MetricsApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = MetricsDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class MetricsDelegate: NSObject, NSApplicationDelegate {
    private let model = MetricsModel()
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        showDesktop()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Metrics"
        item.button?.target = self
        item.button?.action = #selector(toggleMenu)
        statusItem = item
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MetricsMenu(model: model) { [weak self] in self?.showDesktop() })
        NotificationCenter.default.addObserver(
            self, selector: #selector(position),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func showDesktop() {
        guard AppearanceEnvironment.value("WIDGETS") != "" else { return }
        if panel == nil {
            let scale = CatsTypography.configured.scale
            let size = CGSize(width: 340 * scale, height: 170 * scale)
            let window = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.level = NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            let content = NSHostingView(rootView: LiveMetricsCard(model: model))
            content.sizingOptions = []
            window.contentView = content
            window.setContentSize(size)
            panel = window
        }
        position()
        panel?.orderFrontRegardless()
    }

    @objc private func position() {
        guard let panel, let frame = NSScreen.screens.first?.visibleFrame else { return }
        let margin = min(200, max(0, Double(AppearanceEnvironment.value("MARGIN") ?? "24") ?? 24))
        let position = AppearanceEnvironment.value("POSITION") ?? "bottom-left"
        let x =
            position.hasSuffix("right")
            ? frame.maxX - margin - panel.frame.width : frame.minX + margin
        let y =
            position.hasPrefix("top")
            ? frame.maxY - margin - panel.frame.height : frame.minY + margin
        panel.setFrameOrigin(NSPoint(x: max(frame.minX, x), y: max(frame.minY, y)))
    }

    @objc private func toggleMenu() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        model.stop()
    }
}
