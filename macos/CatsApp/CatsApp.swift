import SwiftUI
import WidgetKit

@MainActor final class AppState: ObservableObject {
    @Published var reading = SharedStorage.read()
    @Published var error: String?
    private var collector: Process?
    private var timer: Timer?
    private var lastReload = Date.distantPast
    private var pendingReload = false

    init() {
        startCollector()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func startCollector() {
        guard collector?.isRunning != true else { return }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cats")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { error = "Collector missing. Rebuild Cats with scripts/build.sh."; return }
        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["CATS_DATA_DIR"] = SharedStorage.directory.path
        process.environment = environment
        do { try process.run(); collector = process; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func refresh() {
        let next = SharedStorage.read(previous: reading.state)
        if next.state != reading.state || next.unavailable != reading.unavailable { pendingReload = true }
        reading = next
        if pendingReload && Date().timeIntervalSince(lastReload) >= 60 {
            WidgetCenter.shared.reloadAllTimelines()
            lastReload = Date(); pendingReload = false
        }
    }
    func stop() { timer?.invalidate(); collector?.terminate() }
    func command(_ value: String) {
        do { try SharedStorage.command(value); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

@main struct CatsApp: App {
    @StateObject private var model = AppState()
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            HStack(spacing: 5) {
                Text("C").font(.system(size: 13, weight: .semibold))
                Text(model.reading.state.hasUsage ? Display.money(model.reading.state.today.spendUsd) : "Cats")
            }
        }.menuBarExtraStyle(.window)
        Window("Cats", id: "cats") {
            DashboardView(model: model)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
                .onOpenURL { _ in NSApplication.shared.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 820, height: 600).windowResizability(.contentSize).windowStyle(.hiddenTitleBar)
    }
}
