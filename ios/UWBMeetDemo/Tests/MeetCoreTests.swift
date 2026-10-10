import XCTest
@testable import MeetCore

final class MeetCoreTests: XCTestCase {
    func testNeedsSustainedCloseSamplesAndOnlyTriggersOnce() {
        var gate = ProximityGate()
        XCTAssertFalse(gate.update(distance: 0.25, at: 0))
        XCTAssertFalse(gate.update(distance: 0.25, at: 0.25))
        XCTAssertTrue(gate.update(distance: 0.25, at: 0.51))
        XCTAssertFalse(gate.update(distance: 0.20, at: 0.60))
    }
    func testMissingReadingsCannotFinishDwell() {
        var gate = ProximityGate()
        XCTAssertFalse(gate.update(distance: 0.20, at: 0))
        XCTAssertFalse(gate.update(distance: 0.20, at: 1))
        XCTAssertFalse(gate.update(distance: nil, at: 1.1))
        XCTAssertFalse(gate.update(distance: 0.20, at: 1.2))
        XCTAssertFalse(gate.update(distance: .nan, at: 1.3))
        XCTAssertFalse(gate.update(distance: -1, at: 1.4))
        XCTAssertFalse(gate.update(distance: 0.20, at: 1.5))
    }
    func testFarSampleResetsDwell() {
        var gate = ProximityGate()
        _ = gate.update(distance: 0.20, at: 0)
        _ = gate.update(distance: 0.50, at: 0.25)
        XCTAssertFalse(gate.update(distance: 0.20, at: 0.50))
    }
    func testConsentRequiresBothDistanceSignalsAndBothPeople() {
        var state = ExchangeState()
        state.consentFromPeer()
        XCTAssertFalse(state.consentLocally())
        state.markPeerNear()
        XCTAssertFalse(state.consentLocally())
        state.markLocalNear()
        XCTAssertTrue(state.consentLocally())
        XCTAssertTrue(state.canExchange)
        XCTAssertFalse(state.complete)
        XCTAssertTrue(state.markCardStored())
        XCTAssertFalse(state.complete)
        XCTAssertTrue(state.markPeerReceipt())
        XCTAssertTrue(state.complete)
    }
    func testCancellationPreventsSharingAndSuccess() {
        var state = ExchangeState()
        state.markLocalNear(); state.markPeerNear()
        _ = state.consentLocally(); state.consentFromPeer()
        state.cancel()
        XCTAssertFalse(state.canExchange)
        XCTAssertFalse(state.markCardStored())
        XCTAssertFalse(state.markPeerReceipt())
    }
    func testTCPFragmentationAndCoalescing() throws {
        let first = Data("first".utf8), second = Data("second".utf8)
        let a = try FrameBuffer.frame(first), b = try FrameBuffer.frame(second)
        var buffer = FrameBuffer()
        XCTAssertEqual(try buffer.append(Data(a.prefix(2))), [])
        XCTAssertEqual(try buffer.append(Data(a.dropFirst(2)) + b), [first, second])
    }
    func testOversizedAndEmptyFramesRejected() {
        var buffer = FrameBuffer()
        XCTAssertThrowsError(try buffer.append(Data([0, 2, 0, 0])))
        XCTAssertThrowsError(try FrameBuffer.frame(Data()))
        XCTAssertThrowsError(try FrameBuffer.frame(Data(repeating: 0, count: FrameBuffer.maximum + 1)))
    }
    func testReplayedOrWrongSessionPacketsRejected() {
        let session = UUID()
        func message(_ kind: MessageKind, _ sequence: Int, _ id: UUID) -> WireMessage {
            WireMessage(version: 1, session: id, sequence: sequence, kind: kind, profile: nil, token: nil, contact: nil)
        }
        var guardState = SequenceGuard()
        XCTAssertFalse(guardState.accept(message(.consent, 0, session)))
        XCTAssertTrue(guardState.accept(message(.hello, 0, session)))
        XCTAssertFalse(guardState.accept(message(.hello, 0, session)))
        XCTAssertFalse(guardState.accept(message(.near, 1, UUID())))
        XCTAssertTrue(guardState.accept(message(.near, 1, session)))
    }
}
