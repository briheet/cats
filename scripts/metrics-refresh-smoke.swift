import Combine
import Foundation

@main enum MetricsRefreshSmoke {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        setenv("CATS_METRICS_DATA_DIR", directory.path, 1)
        setenv("CATS_METRICS_EXTERNAL_COLLECTOR", "1", 1)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var state = MetricsState()
        state.cpuPercent = 10
        let file = directory.appendingPathComponent("state.json")
        try encoder.encode(state).write(to: file, options: .atomic)
        try Data(String(Date().timeIntervalSince1970).utf8).write(
            to: directory.appendingPathComponent("heartbeat"))
        let model = MetricsModel()
        model.start()
        defer { model.stop() }
        precondition(model.reading.state.cpuPercent == 10)
        var publications = 0
        let subscription = model.$reading.sink { _ in publications += 1 }
        defer { subscription.cancel() }
        state.cpuPercent = 25
        try encoder.encode(state).write(to: file, options: .atomic)
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        precondition(model.reading.state.cpuPercent == 25)
        precondition(publications == 2)
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        precondition(publications == 2, "Unchanged metrics republished")
        try Data("invalid".utf8).write(to: file, options: .atomic)
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        precondition(model.reading.state.cpuPercent == 25 && model.reading.unavailable)
        print("PASS: metrics startup, two-second refresh, deduplication, corrupt-state retention")
    }
}
