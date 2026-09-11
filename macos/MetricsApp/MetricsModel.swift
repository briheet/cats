import Combine
import Foundation

@MainActor final class MetricsModel: ObservableObject {
    @Published private(set) var reading = MetricsReading()
    @Published private(set) var error: String?
    private var store: MetricsStore?
    private var collector: Process?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let env = ProcessInfo.processInfo.environment
        let executable =
            env["CATS_METRICS_COLLECTOR"].map(URL.init(fileURLWithPath:))
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cats-metrics")
        do {
            let directory: URL
            if let configured = env["CATS_METRICS_DATA_DIR"], configured.hasPrefix("/") {
                directory = URL(fileURLWithPath: configured)
            } else {
                let resolver = Process()
                resolver.executableURL = executable
                resolver.arguments = ["config"]
                let output = Pipe()
                resolver.standardOutput = output
                try resolver.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                resolver.waitUntilExit()
                guard resolver.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
                struct Configuration: Decodable { var dataDir: String }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                directory = URL(
                    fileURLWithPath: try decoder.decode(Configuration.self, from: data).dataDir)
            }
            store = MetricsStore(directory: directory)
            refresh()
            guard !reading.accessDenied else { return }
            if env["CATS_METRICS_EXTERNAL_COLLECTOR"] != "1" && reading.unavailable {
                let child = Process()
                child.executableURL = executable
                child.arguments = ["--data-dir", directory.path]
                try child.run()
                collector = child
            }
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        } catch { self.error = "Metrics unavailable: \(error.localizedDescription)" }
    }

    private func refresh() {
        guard let store else { return }
        let next = store.read(previous: reading.state)
        if next != reading { reading = next }
        if next.accessDenied {
            stop()
            error =
                "Storage access denied. Correct the configuration before reopening Cats Metrics."
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if collector?.isRunning == true { collector?.terminate() }
        collector = nil
    }
}
