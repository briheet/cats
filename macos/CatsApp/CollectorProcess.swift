import Foundation

/// Owns only a collector launched by this app. Home Manager collectors remain independent.
@MainActor final class CollectorProcess {
    private let environment: [String: String]
    private let executable: URL
    private var process: Process?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        executable =
            environment["CATS_LLM_COLLECTOR"].map(URL.init(fileURLWithPath:))
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cats-llm")
    }

    func dataDirectory() throws -> URL {
        if let path = environment["CATS_LLM_DATA_DIR"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        // Rust remains the sole TOML parser and configuration authority.
        struct Configuration: Decodable {
            let dataDir: String
        }
        let resolver = Process()
        resolver.executableURL = executable
        resolver.environment = environment
        resolver.arguments = ["config"]
        let output = Pipe()
        resolver.standardOutput = output
        try resolver.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        resolver.waitUntilExit()
        guard resolver.terminationStatus == 0 else { throw CollectorError.invalidConfiguration }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let configuration = try decoder.decode(Configuration.self, from: data)
        return URL(fileURLWithPath: configuration.dataDir)
    }

    func start(dataDirectory: URL) throws {
        guard environment["CATS_LLM_EXTERNAL_COLLECTOR"] != "1", process?.isRunning != true else {
            return
        }
        let child = Process()
        child.executableURL = executable
        child.environment = environment.merging(["CATS_LLM_DATA_DIR": dataDirectory.path]) {
            _, new in
            new
        }
        try child.run()
        process = child
    }

    func stop() {
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }
}

private enum CollectorError: LocalizedError {
    case invalidConfiguration

    var errorDescription: String? {
        "Cats configuration is invalid. Run cats-llm config to see the error."
    }
}
