import XCTest
@testable import LivescriptCore

final class UtteranceBufferTests: XCTestCase {
    func testDraftHopEveryOnePointFiveSecondsDuringSpeech() {
        var buffer = UtteranceBuffer(
            draftHopSeconds: 1.5,
            pauseSeconds: 0.4,
            maxUtteranceSeconds: 10,
            minimumEnergy: 0.001
        )

        let chunk = Array(repeating: Float(0.05), count: 8_000)
        var draftHops = 0
        for _ in 0..<5 {
            let events = buffer.append(chunk)
            draftHops += events.filter {
                if case .draftHop = $0 { return true }
                return false
            }.count
        }

        XCTAssertGreaterThanOrEqual(draftHops, 1)
    }

    func testDraftHopUsesIncrementalAudio() {
        var buffer = UtteranceBuffer(
            draftHopSeconds: 1.0,
            pauseSeconds: 0.4,
            maxUtteranceSeconds: 10,
            minimumEnergy: 0.001
        )

        let chunk = Array(repeating: Float(0.05), count: 8_000)
        for _ in 0..<4 {
            if let event = buffer.append(chunk).first(where: {
                if case .draftHop = $0 { return true }
                return false
            }), case .draftHop(let audio) = event {
                XCTAssertLessThanOrEqual(audio.count, 16_000)
                XCTAssertGreaterThanOrEqual(audio.count, 8_000)
                return
            }
        }
        XCTFail("Expected a draft hop")
    }

    func testUtteranceCompleteAfterPause() {
        var buffer = UtteranceBuffer(
            draftHopSeconds: 1.5,
            pauseSeconds: 0.4,
            maxUtteranceSeconds: 10,
            minimumEnergy: 0.001
        )

        let speech = Array(repeating: Float(0.05), count: 16_000)
        _ = buffer.append(speech)

        let silence = Array(repeating: Float(0.0001), count: 8_000)
        let events = buffer.append(silence)

        XCTAssertTrue(events.contains {
            if case .utteranceComplete = $0 { return true }
            return false
        })
    }
}
