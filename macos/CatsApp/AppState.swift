import Combine
import Foundation

/// Observable telemetry and collection lifecycle; presentation owns all windows.
@MainActor final class AppState: ObservableObject {
    @Published private(set) var reading = SnapshotReading(state: .empty, unavailable: true)
    @Published private(set) var error: String?
    private let collector = CollectorProcess()
    private var store: SnapshotStore?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        do {
            store = SnapshotStore(directory: try collector.dataDirectory())
        } catch {
            self.error = error.localizedDescription
            return
        }
        refresh()
        guard !reading.accessDenied else { return }
        startCollector()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func startCollector() {
        guard let store, !reading.accessDenied, reading.unavailable else { return }
        do {
            try collector.start(dataDirectory: store.directory)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refresh() {
        guard let store else { return }
        let next = store.read(previous: reading.state)
        if next != reading { reading = next }
        if reading.accessDenied {
            stop()
            error =
                "Storage access denied. Cats is paused; check its configuration before reopening."
        }
    }

    func send(_ action: AgentAction) {
        guard let store, !reading.accessDenied else { return }
        do {
            try store.send(action)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        collector.stop()
    }
}
