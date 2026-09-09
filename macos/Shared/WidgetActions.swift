import AppIntents

struct PauseAgentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Cats-managed agents"
    static var description = IntentDescription("Pause agents launched with cats run. Other agents are observed only.")
    func perform() async throws -> some IntentResult { try SharedStorage.command("pause"); return .result() }
}
struct ResumeAgentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Cats-managed agents"
    func perform() async throws -> some IntentResult { try SharedStorage.command("resume"); return .result() }
}
struct OpenCatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Cats"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
