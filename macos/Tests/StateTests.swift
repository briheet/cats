import XCTest

@testable import CatsShared

final class StateTests: XCTestCase {
    private func temporaryStore() throws -> SnapshotStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return SnapshotStore(directory: directory)
    }

    func testStorageInstancesAreIndependent() throws {
        let first = try temporaryStore()
        let second = try temporaryStore()
        try fixture().write(to: first.directory.appendingPathComponent("cats-state.json"))
        XCTAssertTrue(first.read().state.hasUsage)
        XCTAssertFalse(second.read().state.hasUsage)
    }

    func testPermissionFailureIsReportedWithoutReadingFurtherFiles() throws {
        let store = try temporaryStore()
        let file = store.directory.appendingPathComponent("cats-state.json")
        try fixture().write(to: file)
        addTeardownBlock {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        XCTAssertTrue(store.read().accessDenied)
        XCTAssertTrue(
            SnapshotStore.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: 1)))
        XCTAssertFalse(SnapshotStore.isPermissionDenied(CocoaError(.fileReadNoSuchFile)))
    }

    func testControlMessagesUseTheTypedWireProtocol() throws {
        let store = try temporaryStore()
        let file = store.directory.appendingPathComponent("cats-control.json")
        for action in [AgentAction.pause, .resume] {
            try store.send(action)
            let command = try JSONDecoder().decode(AgentCommand.self, from: Data(contentsOf: file))
            XCTAssertEqual(command.action, action)
        }
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AgentCommand.self, from: Data(#"{"action":"kill"}"#.utf8)
            ))
    }

    func testThemeIsOptionalAndDecodesResolvedColors() throws {
        XCTAssertNil(try TelemetryState.decode(fixture()).theme)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        object["theme"] = [
            "appearance": "dark", "colors": ["surface": "#2e3440", "accent": "#a3be8c"],
        ]
        let state = try TelemetryState.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(state.theme?.appearance, "dark")
        XCTAssertEqual(state.theme?.colors["surface"], "#2e3440")
    }
    func fixture() throws -> Data {
        try Data(
            contentsOf: XCTUnwrap(
                Bundle.module.url(
                    forResource: "state", withExtension: "json", subdirectory: "Fixtures")))
    }
    func testSnapshotDecoding() throws {
        let state = try TelemetryState.decode(fixture())
        XCTAssertEqual(state.today.spendUsd, 13.62)
        XCTAssertEqual(state.today.tokensCache, 300_000)
        XCTAssertEqual(state.agents.first?.name, "backend")
        XCTAssertEqual(state.providers.first?.agentCount, 2)
    }
    func testCorruptedAndMissingFields() {
        XCTAssertThrowsError(try TelemetryState.decode(Data("broken".utf8)))
        XCTAssertThrowsError(try TelemetryState.decode(Data("{}".utf8)))
    }
    func testUnknownSchemaRejected() throws {
        let text = String(decoding: try fixture(), as: UTF8.self).replacingOccurrences(
            of: "\"schema_version\":1", with: "\"schema_version\":99")
        XCTAssertThrowsError(try TelemetryState.decode(Data(text.utf8)))
    }
    func testLargeAndInvalidValues() {
        XCTAssertEqual(Display.tokens(12_800_000), "12.8M")
        XCTAssertEqual(Display.tokens(1_000_000_000), "1B")
        XCTAssertEqual(Display.money(142.8), "$142.80")
        XCTAssertEqual(Display.money(.infinity), "—")
        XCTAssertEqual(Display.tokens(.nan), "—")
        XCTAssertEqual(Display.runtime(.infinity), "—")
        XCTAssertEqual(Display.runtime(720), "12m")
    }

    func testMissingStaleAndCorruptedSnapshotRetainsLastGoodState() throws {
        let store = try temporaryStore()
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(store.read(now: now).unavailable)
        XCTAssertFalse(store.read(now: now).state.hasUsage)
        let file = store.directory.appendingPathComponent("cats-state.json")
        try fixture().write(to: file)
        let reading = store.read(now: now)
        XCTAssertTrue(reading.state.hasUsage)
        XCTAssertTrue(reading.unavailable)
        try Data("broken".utf8).write(to: file)
        let bad = store.read(previous: reading.state, now: now)
        XCTAssertTrue(bad.invalid)
        XCTAssertEqual(bad.state.today.spendUsd, 13.62)
        let heartbeat = store.directory.appendingPathComponent("heartbeat")
        try Data("1000".utf8).write(to: heartbeat)
        XCTAssertFalse(store.read(now: now).unavailable)
        try Data("nan".utf8).write(to: heartbeat)
        XCTAssertTrue(store.read(now: now).unavailable)
    }
}
