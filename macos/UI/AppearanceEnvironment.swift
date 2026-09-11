import Foundation

// Resolved at build time; one app never reads the other app's environment.
enum AppearanceEnvironment {
    #if METRICS
        static let prefix = "CATS_METRICS_"
    #else
        static let prefix = "CATS_LLM_"
    #endif
    static func value(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[prefix + key]
    }
}
