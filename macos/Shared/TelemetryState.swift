import Foundation

struct TelemetryState: Codable, Equatable {
    var theme: ThemeState?
    var schemaVersion = 1
    var generatedAt: Double = 0
    var lastEventAt: Double?
    var hasUsage = false
    var today = Today()
    var providers: [ProviderUsage] = []
    var agents: [Agent] = []
    var activeAgents = 0
    var waitingAgents = 0
    var failedAgents = 0
    var history = History()
    var collectorErrors = 0

    struct Today: Codable, Equatable {
        var spendUsd: Double = 0
        var budgetUsd: Double = 20
        var budgetFraction: Double = 0
        var budgetState = "normal"
        var burnRatePerHour: Double = 0
        var projectedDailySpend: Double?
        var tokensTotal: Double = 0
        var tokensInput: Double = 0
        var tokensOutput: Double = 0
        var tokensCache: Double = 0
        var unpricedEvents = 0
    }
    struct History: Codable, Equatable { var hourlySpend: [Double] = [] }
    static let empty = TelemetryState()
    static func decode(_ data: Data) throws -> TelemetryState {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let state = try decoder.decode(Self.self, from: data)
        guard state.schemaVersion == 1, state.generatedAt.isFinite,
            state.today.spendUsd.isFinite, state.today.spendUsd >= 0,
            state.today.budgetUsd.isFinite, state.today.budgetUsd > 0,
            state.today.budgetFraction.isFinite
        else { throw CocoaError(.coderReadCorrupt) }
        return state
    }
}
struct ThemeState: Codable, Equatable {
    var appearance: String
    var colors: [String: String]
}
struct ProviderUsage: Codable, Identifiable, Equatable {
    var name: String
    var spendUsd: Double
    var tokens: Double
    var fraction: Double
    var agentCount: Int?
    var id: String { name }
}
struct Agent: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var provider: String
    var status: String
    var elapsedSeconds: Double
    var tokens: Double
    var spendUsd: Double
}
