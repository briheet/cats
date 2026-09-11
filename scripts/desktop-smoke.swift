import AppKit

// Inspect only the test process's window metadata; never capture the screen.
guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else { exit(2) }
let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
let panels = windows.filter {
    ($0[kCGWindowOwnerPID as String] as? Int32) == pid
        && ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.desktopIconWindow))
            + 1
}
let sizes = [
    "large": [760.0, 250.0], "medium": [340.0, 170.0], "small": [170.0, 170.0],
    "medium-agents": [340.0, 170.0], "small-agents": [170.0, 170.0],
    "small-burn-rate": [170.0, 170.0],
]
let configuredSize = Double(ProcessInfo.processInfo.environment["CATS_LLM_FONT_SIZE"] ?? "12") ?? 12
let scale = min(20, max(10, configuredSize.isFinite ? configuredSize : 12)) / 12
let selected = (ProcessInfo.processInfo.environment["CATS_LLM_WIDGETS"] ?? "large,medium")
    .split(separator: ",").map(String.init)
guard panels.count == selected.count else {
    fputs("Expected \(selected.count) desktop panels; found \(panels.count)\n", stderr)
    exit(1)
}
for panel in panels {
    guard panel[kCGWindowIsOnscreen as String] as? Bool == true else {
        fputs("Test panel is not onscreen: \(panel)\n", stderr)
        exit(1)
    }
    guard let bounds = panel[kCGWindowBounds as String] as? [String: Double],
        let width = bounds["Width"], let height = bounds["Height"],
        selected.contains(where: { name in
            guard let size = sizes[name] else { return false }
            return abs(size[0] * scale - width) <= 1 && abs(size[1] * scale - height) <= 1
        })
    else {
        fputs("Unexpected panel bounds: \(panel)\n", stderr)
        exit(1)
    }
}
print("PASS: \(selected.count) desktop panels with expected levels and sizes")
