import Foundation

enum AgentAction: String, Codable {
    case pause
    case resume
}

struct AgentCommand: Codable {
    let action: AgentAction
}

struct SnapshotReading: Equatable {
    var state: TelemetryState
    var unavailable = false
    var invalid = false
    var accessDenied = false

    var warning: String? {
        if accessDenied { return "Storage access denied" }
        if invalid { return "Snapshot unreadable" }
        if unavailable { return "Collector unavailable" }
        if state.collectorErrors > 0 { return "A source needs attention" }
        if state.today.unpricedEvents > 0 { return "Partial estimate · unknown pricing" }
        return nil
    }
}

/// Reads snapshots from one explicit directory. No mutable global paths or App Groups.
struct SnapshotStore {
    let directory: URL

    func read(previous: TelemetryState = .empty, now: Date = Date()) -> SnapshotReading {
        var accessDenied = false
        func readFile(_ name: String) -> Data? {
            do {
                return try Data(
                    contentsOf: directory.appendingPathComponent(name), options: .mappedIfSafe)
            } catch {
                accessDenied = accessDenied || Self.isPermissionDenied(error)
                return nil
            }
        }
        let data = readFile("cats-state.json")
        let state = data.flatMap { try? TelemetryState.decode($0) }
        // A denied snapshot must not cause a second protected-file access.
        let heartbeatData = accessDenied ? nil : readFile("heartbeat")
        let heartbeat = heartbeatData.flatMap { String(data: $0, encoding: .utf8) }.flatMap(
            Double.init)
        let isFresh =
            heartbeat.map { $0.isFinite && now.timeIntervalSince1970 - $0 <= 180 } ?? false
        return SnapshotReading(
            state: state ?? previous,
            unavailable: !isFresh,
            invalid: data != nil && state == nil,
            accessDenied: accessDenied
        )
    }

    func send(_ action: AgentAction) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(AgentCommand(action: action))
        try data.write(to: directory.appendingPathComponent("cats-control.json"), options: .atomic)
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
            [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code)
        {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, [1, 13].contains(error.code) {
            return true
        }
        return (error.userInfo[NSUnderlyingErrorKey] as? NSError).map(isPermissionDenied) ?? false
    }
}
