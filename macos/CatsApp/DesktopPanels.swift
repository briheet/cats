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
            for kind in DesktopCardKind.enabled(in: ProcessInfo.processInfo.environment) {
                let scale = CatsTypography.configured.scale
                let size = CGSize(width: kind.size.width * scale, height: kind.size.height * scale)
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
                let content = NSHostingView(
                    rootView: LiveDesktopCard(model: model, kind: kind))
                // Panel geometry owns sizing; intrinsic SwiftUI updates must not resize it.
                content.sizingOptions = []
                panel.contentView = content
                panel.setContentSize(size)
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
        let leftAligned = env["CATS_POSITION"] == "top-left"
        let rowWidth = min(
            frame.width - 2 * margin,
            max(panels.map { $0.frame.width }.max() ?? 0, 696 * CatsTypography.configured.scale))
        var top = frame.maxY - margin
        var used: CGFloat = 0
        var rowHeight: CGFloat = 0
        for panel in panels {
            if used > 0 && used + panel.frame.width > rowWidth {
                top -= rowHeight + 16
                used = 0
                rowHeight = 0
            }
            let x =
                leftAligned
                ? frame.minX + margin + used
                : frame.maxX - margin - used - panel.frame.width
            panel.setFrameOrigin(NSPoint(x: max(frame.minX, x), y: top - panel.frame.height))
            used += panel.frame.width + 16
            rowHeight = max(rowHeight, panel.frame.height)
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
