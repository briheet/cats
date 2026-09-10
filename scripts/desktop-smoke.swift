import AppKit

// Inspect only the test process's window metadata; never capture the screen.
guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else { exit(2) }
let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
let panels = windows.filter {
    ($0[kCGWindowOwnerPID as String] as? Int32) == pid
        && ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.desktopIconWindow))
            + 1
}
guard panels.count == 2 else {
    fputs("Expected two desktop panels; found \(panels.count)\n", stderr)
    exit(1)
}
for panel in panels {
    guard panel[kCGWindowIsOnscreen as String] as? Bool == true else { exit(1) }
    guard let bounds = panel[kCGWindowBounds as String] as? [String: Double],
        bounds["Width"] == 340,
        [170.0, 340.0].contains(bounds["Height"] ?? 0)
    else { exit(1) }
}
print("PASS: two desktop panels with expected levels and sizes")
