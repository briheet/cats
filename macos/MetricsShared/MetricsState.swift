import Foundation

struct MetricsState: Codable, Equatable {
    var schemaVersion = 1
    var generatedAt: Double = 0
    var theme = ThemeState(appearance: "system", colors: [:])
    var cpuPercent: Double?
    var memory: Memory?
    var networks: [Network] = []
    var disk: Disk?
    var battery: Battery?
    var thermal: Thermal?
    var lowPowerMode = false
    var history: [Point] = []

    struct Memory: Codable, Equatable {
        var used: Double
        var total: Double
        var swapUsed: Double
    }
    struct Network: Codable, Equatable {
        var interface: String
        var receivedPerSecond: Double?
        var transmittedPerSecond: Double?
    }
    struct Disk: Codable, Equatable {
        var available: Double
        var total: Double
    }
    struct Battery: Codable, Equatable {
        var percent: Double
        var charging: Bool?
        var pluggedIn: Bool?
    }
    enum Thermal: String, Codable { case nominal, fair, serious, critical }
    struct Point: Codable, Equatable {
        var time: Double
        var cpuPercent: Double?
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let state = try decoder.decode(Self.self, from: data)
        func valid(_ value: Double?, maximum: Double = .greatestFiniteMagnitude) -> Bool {
            value.map { $0.isFinite && $0 >= 0 && $0 <= maximum } ?? true
        }
        guard state.schemaVersion == 1, valid(state.generatedAt),
            valid(state.cpuPercent, maximum: 100), valid(state.battery?.percent, maximum: 100),
            valid(state.memory?.used, maximum: state.memory?.total ?? 0),
            valid(state.memory?.total), valid(state.memory?.swapUsed),
            valid(state.disk?.available, maximum: state.disk?.total ?? 0), valid(state.disk?.total),
            state.networks.allSatisfy({
                valid($0.receivedPerSecond) && valid($0.transmittedPerSecond)
            }),
            state.history.count <= 60,
            state.history.allSatisfy({ valid($0.time) && valid($0.cpuPercent, maximum: 100) })
        else { throw CocoaError(.coderReadCorrupt) }
        return state
    }
}

struct MetricsReading: Equatable {
    var state = MetricsState()
    var unavailable = true
    var invalid = false
    var accessDenied = false
}

struct MetricsStore {
    var directory: URL
    func read(previous: MetricsState, now: Date = Date()) -> MetricsReading {
        var latest = previous
        do {
            let bytes = try Data(contentsOf: directory.appendingPathComponent("state.json"))
            let state = try MetricsState.decode(bytes)
            latest = state
            let heartbeat = try String(
                contentsOf: directory.appendingPathComponent("heartbeat"), encoding: .utf8)
            let stamp = Double(heartbeat.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let age = now.timeIntervalSince1970 - stamp
            return MetricsReading(
                state: state, unavailable: !stamp.isFinite || age < -5 || age > 10)
        } catch {
            return MetricsReading(
                state: latest, unavailable: true, invalid: true,
                accessDenied: Self.permissionDenied(error))
        }
    }
    static func permissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain
            && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code)
        {
            return true
        }
        if error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code) { return true }
        return (error.userInfo[NSUnderlyingErrorKey] as? NSError).map(permissionDenied) ?? false
    }
}
