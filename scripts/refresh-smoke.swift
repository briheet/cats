import Combine
import Foundation

@main struct RefreshSmoke {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        setenv("CATS_LLM_DATA_DIR", directory.path, 1)
        setenv("CATS_LLM_EXTERNAL_COLLECTOR", "1", 1)
        var state = try TelemetryState.decode(
            Data(
                contentsOf:
                    URL(fileURLWithPath: "macos/Tests/Fixtures/state.json")))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let snapshot = directory.appendingPathComponent("state.json")
        try encoder.encode(state).write(to: snapshot, options: .atomic)
        try Data(String(Date().timeIntervalSince1970).utf8)
            .write(to: directory.appendingPathComponent("heartbeat"))
        let model = AppState()
        model.start()
        defer { model.stop() }
        precondition(model.reading.state.today.spendUsd == state.today.spendUsd)
        var publications = 0
        let subscription = model.$reading.sink { _ in publications += 1 }
        defer { subscription.cancel() }
        state.today.spendUsd += 1
        try encoder.encode(state).write(to: snapshot, options: .atomic)
        RunLoop.main.run(until: Date().addingTimeInterval(6))
        precondition(model.reading.state.today.spendUsd == state.today.spendUsd)
        precondition(publications == 2, "Expected initial reading and one update")
        RunLoop.main.run(until: Date().addingTimeInterval(6))
        precondition(publications == 2, "Unchanged snapshot was republished")
        print("PASS: startup read, five-second refresh, unchanged-state suppression")
    }
}
