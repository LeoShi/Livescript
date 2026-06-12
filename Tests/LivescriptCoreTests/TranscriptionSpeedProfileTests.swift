import XCTest
@testable import LivescriptCore

final class TranscriptionSpeedProfileTests: XCTestCase {
    func testSmartProfileUsesSenseVoiceDraftAndDistilRefine() {
        XCTAssertTrue(TranscriptionSpeedProfile.smart.usesSmartCaptions)
        XCTAssertEqual(TranscriptionSpeedProfile.smart.engine, .senseVoice)
        XCTAssertEqual(TranscriptionSpeedProfile.smart.modelLabel, "SenseVoice + distil-large-v3")
        XCTAssertEqual(TranscriptionSpeedProfile.refineWhisperModelVariant, "distil-large-v3")
    }

    func testLegacyRealtimeMapsToSmartCaptions() {
        XCTAssertTrue(TranscriptionSpeedProfile.usesSmartCaptions(for: "realtime"))
    }

    func testBalancedAndQualityUseWhisperOnly() {
        XCTAssertFalse(TranscriptionSpeedProfile.balanced.usesSmartCaptions)
        XCTAssertFalse(TranscriptionSpeedProfile.quality.usesSmartCaptions)
        XCTAssertEqual(TranscriptionSpeedProfile.whisperModelVariant(for: TranscriptionSpeedProfile.quality.rawValue), "large-v3-v20240930_626MB")
    }

    func testRealtimeEnergyGateAcceptsQuietMeetingAudio() {
        XCTAssertTrue(
            TranscriptionPipelineSupport.shouldTranscribeSlice(
                energy: 0.004,
                minimumEnergy: TranscriptionSpeedProfile.smart.minimumEnergy
            )
        )
    }

    func testEchoBleedAllowsClearlyLouderMicSpeech() {
        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldSkipEchoBleed(
                speakerLabel: "You",
                sourceMode: .mixed,
                micEnergy: 0.03,
                systemReferenceEnergy: 0.01,
                microphoneInputKind: .builtIn
            )
        )
    }
}
