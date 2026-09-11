import Foundation
import XCTest

@testable import CatsShared

final class MetricsTests: XCTestCase {
    private func encode(_ state: MetricsState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(state)
    }
    func testUnavailableValuesAndBatterylessMac() throws {
        let state = try MetricsState.decode(encode(MetricsState()))
        XCTAssertNil(state.cpuPercent)
        XCTAssertNil(state.battery)
        XCTAssertNil(state.thermal)
    }
    func testRejectsBadSchemaRangesAndUnboundedHistory() throws {
        var state = MetricsState()
        state.schemaVersion = 99
        XCTAssertThrowsError(try MetricsState.decode(encode(state)))
        state.schemaVersion = 1
        state.cpuPercent = 101
        XCTAssertThrowsError(try MetricsState.decode(encode(state)))
        state.cpuPercent = 20
        state.memory = .init(used: 101, total: 100, swapUsed: 0)
        XCTAssertThrowsError(try MetricsState.decode(encode(state)))
        state.memory = nil
        state.history = Array(repeating: .init(time: 1, cpuPercent: 20), count: 61)
        XCTAssertThrowsError(try MetricsState.decode(encode(state)))
    }
    func testStoreKeepsLastGoodStateAndReportsStaleness() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let store = MetricsStore(directory: directory)
        var state = MetricsState()
        state.generatedAt = 100
        state.cpuPercent = 17
        let now = Date(timeIntervalSince1970: 105)
        XCTAssertTrue(store.read(previous: state, now: now).unavailable)
        try encode(state).write(to: directory.appendingPathComponent("state.json"))
        try Data("100".utf8).write(to: directory.appendingPathComponent("heartbeat"))
        let first = store.read(previous: state, now: now)
        XCTAssertFalse(first.unavailable)
        XCTAssertEqual(first, store.read(previous: state, now: now))
        XCTAssertTrue(
            store.read(previous: state, now: Date(timeIntervalSince1970: 111)).unavailable)
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("state.json"))
        let broken = store.read(previous: state, now: now)
        XCTAssertEqual(broken.state, state)
        XCTAssertTrue(broken.invalid)
        XCTAssertTrue(broken.unavailable)
    }
    func testProductsDoNotDecodeEachOthersSnapshots() throws {
        XCTAssertThrowsError(try TelemetryState.decode(encode(MetricsState())))
    }
}
