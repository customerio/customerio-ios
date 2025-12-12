@testable import CioMessagingInApp
import XCTest

class SseConnectionStateTest: XCTestCase {
    // MARK: - State Values

    func test_disconnected_description() {
        let state = SseConnectionState.disconnected
        XCTAssertEqual(state.description, "disconnected")
    }

    func test_connecting_description() {
        let state = SseConnectionState.connecting
        XCTAssertEqual(state.description, "connecting")
    }

    func test_connected_description() {
        let state = SseConnectionState.connected
        XCTAssertEqual(state.description, "connected")
    }

    // MARK: - Equatable

    func test_equatable_sameStates_expectEqual() {
        XCTAssertEqual(SseConnectionState.disconnected, SseConnectionState.disconnected)
        XCTAssertEqual(SseConnectionState.connecting, SseConnectionState.connecting)
        XCTAssertEqual(SseConnectionState.connected, SseConnectionState.connected)
    }

    func test_equatable_differentStates_expectNotEqual() {
        XCTAssertNotEqual(SseConnectionState.disconnected, SseConnectionState.connecting)
        XCTAssertNotEqual(SseConnectionState.connecting, SseConnectionState.connected)
        XCTAssertNotEqual(SseConnectionState.connected, SseConnectionState.disconnected)
    }
}
