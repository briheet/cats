import Foundation

enum SharedStorage {
    static var appGroup: String { Bundle.main.object(forInfoDictionaryKey: "CatsAppGroup") as? String ?? "group.dev.cats.shared" }
    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["CATS_DATA_DIR"] { return URL(fileURLWithPath: path) }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/\(appGroup)")
    }
    static func read(previous: WidgetState = .empty) -> Reading {
        let data = try? Data(contentsOf: directory.appendingPathComponent("cats-state.json"), options: .mappedIfSafe)
        let state = data.flatMap { try? WidgetState.decode($0) }
        let heartbeat = (try? String(contentsOf: directory.appendingPathComponent("heartbeat"), encoding: .utf8)).flatMap(Double.init) ?? 0
        return Reading(state: state ?? previous, unavailable: Date().timeIntervalSince1970 - heartbeat > 180,
                       invalid: data != nil && state == nil)
    }
    static func command(_ action: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["action": action])
        try data.write(to: directory.appendingPathComponent("cats-control.json"), options: .atomic)
    }
}
struct Reading {
    var state: WidgetState
    var unavailable = false
    var invalid = false
}
