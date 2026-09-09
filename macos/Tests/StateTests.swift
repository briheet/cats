import XCTest
@testable import CatsShared

final class StateTests: XCTestCase {
    func testThemeIsOptionalAndDecodesResolvedColors() throws {
        XCTAssertNil(try WidgetState.decode(fixture()).theme)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        object["theme"] = ["appearance": "dark", "colors": ["surface": "#2e3440", "accent": "#a3be8c"]]
        let state = try WidgetState.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(state.theme?.appearance, "dark")
        XCTAssertEqual(state.theme?.colors["surface"], "#2e3440")
    }
    func fixture() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "state", withExtension: "json", subdirectory: "Fixtures")))
    }
    func testSnapshotDecoding() throws {
        let state = try WidgetState.decode(fixture())
        XCTAssertEqual(state.today.spendUsd, 13.62)
        XCTAssertEqual(state.today.tokensCache, 300_000)
        XCTAssertEqual(state.agents.first?.name, "backend")
        XCTAssertEqual(state.providers.first?.agentCount, 2)
    }
    func testCorruptedAndMissingFields() {
        XCTAssertThrowsError(try WidgetState.decode(Data("broken".utf8)))
        XCTAssertThrowsError(try WidgetState.decode(Data("{}".utf8)))
    }
    func testUnknownSchemaRejected() throws {
        let text = String(decoding: try fixture(), as: UTF8.self).replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":99")
        XCTAssertThrowsError(try WidgetState.decode(Data(text.utf8)))
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
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir); unsetenv("CATS_DATA_DIR") }
        setenv("CATS_DATA_DIR", dir.path, 1)
        XCTAssertTrue(SharedStorage.read().unavailable)
        XCTAssertFalse(SharedStorage.read().state.hasUsage)
        try fixture().write(to: dir.appendingPathComponent("cats-state.json"))
        let reading = SharedStorage.read()
        XCTAssertTrue(reading.state.hasUsage)
        XCTAssertTrue(reading.unavailable)
        try Data("broken".utf8).write(to: dir.appendingPathComponent("cats-state.json"))
        let bad = SharedStorage.read(previous: reading.state)
        XCTAssertTrue(bad.invalid)
        XCTAssertEqual(bad.state.today.spendUsd, 13.62)
        try String(Date().timeIntervalSince1970).write(to: dir.appendingPathComponent("heartbeat"), atomically: true, encoding: .utf8)
        XCTAssertFalse(SharedStorage.read().unavailable)
    }
}
