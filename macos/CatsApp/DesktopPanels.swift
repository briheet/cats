import AppKit
import SwiftUI

// Own windows, not WidgetKit: no App Group, Accessibility or screen capture.
@MainActor final class DesktopPanels {
    private var panels: [NSPanel] = []
    private var observer: NSObjectProtocol?
    private let model: AppState

    init(model: AppState) {
        self.model = model
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.position() }
        }
    }

    func show() {
        if panels.isEmpty {
            for kind in DesktopCardKind.allCases {
                let size = kind.size
                let panel = NSPanel(
                    contentRect: NSRect(origin: .zero, size: size),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.hidesOnDeactivate = false
                panel.isMovableByWindowBackground = true
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                // Above wallpaper, below ordinary application windows.
                panel.level = NSWindow.Level(
                    rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
                panel.contentView = NSHostingView(
                    rootView: LiveDesktopCard(model: model, kind: kind))
                panels.append(panel)
            }
        }
        position()
        for panel in panels {
            panel.orderFrontRegardless()
        }
    }

    private func position() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let env = ProcessInfo.processInfo.environment
        let margin = CGFloat(min(200, max(0, Double(env["CATS_MARGIN"] ?? "24") ?? 24)))
        var top = frame.maxY - margin
        for panel in panels {
            let x =
                env["CATS_POSITION"] == "top-left"
                ? frame.minX + margin : frame.maxX - panel.frame.width - margin
            panel.setFrameOrigin(NSPoint(x: x, y: max(frame.minY, top - panel.frame.height)))
            top -= panel.frame.height + 16
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}

private struct LiveDesktopCard: View {
    @ObservedObject var model: AppState
    let kind: DesktopCardKind
    var body: some View {
        DesktopCard(kind: kind, reading: model.reading)
    }
}
