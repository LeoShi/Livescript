import XCTest
@testable import LivescriptCore

final class TranscriptionPipelineSupportTests: XCTestCase {
    func testPopAudioSliceReturnsFixedWindowAndShrinksBuffer() {
        var buffer = Array(repeating: Float(0.1), count: 10)
        let slice = TranscriptionPipelineSupport.popAudioSlice(from: &buffer, chunkSize: 4)

        XCTAssertEqual(slice?.count, 4)
        XCTAssertEqual(buffer.count, 6)
    }

    func testPopAudioSliceReturnsNilUntilEnoughSamples() {
        var buffer = Array(repeating: Float(0.1), count: 3)
        XCTAssertNil(TranscriptionPipelineSupport.popAudioSlice(from: &buffer, chunkSize: 4))
        XCTAssertEqual(buffer.count, 3)
    }

    func testLooksLikeHallucinationBlocksKnownSilencePhrases() {
        XCTAssertTrue(TranscriptionPipelineSupport.looksLikeHallucination("Okay."))
        XCTAssertTrue(TranscriptionPipelineSupport.looksLikeHallucination(" okay "))
        XCTAssertTrue(TranscriptionPipelineSupport.looksLikeHallucination("Thank you."))
        XCTAssertFalse(TranscriptionPipelineSupport.looksLikeHallucination("Let's review the roadmap."))
    }

    func testLooksLikeFragmentHallucinationBlocksSenseVoiceChineseSpam() {
        let fragments = ["我。", "我斑。", "我.", ".", "你斑。", "我。", "我.", "我放。"]
        for fragment in fragments {
            XCTAssertTrue(
                TranscriptionPipelineSupport.looksLikeFragmentHallucination(fragment),
                "Expected fragment hallucination for: \(fragment)"
            )
        }
        XCTAssertFalse(TranscriptionPipelineSupport.looksLikeFragmentHallucination("我们今天讨论一下预算。"))
    }

    func testNearDuplicateShortFragmentBlocksRepeatedMicroLines() {
        XCTAssertTrue(
            TranscriptionPipelineSupport.isNearDuplicateShortFragment("我.", lastFinalText: "我。")
        )
        XCTAssertTrue(
            TranscriptionPipelineSupport.isNearDuplicateShortFragment("我斑。", lastFinalText: "我。")
        )
        XCTAssertFalse(
            TranscriptionPipelineSupport.isNearDuplicateShortFragment(
                "我们今天讨论一下预算。",
                lastFinalText: "我。"
            )
        )
    }

    func testLooksLikeSoundAnnotationBlocksNoiseCaptions() {
        XCTAssertTrue(TranscriptionPipelineSupport.looksLikeSoundAnnotation("(keyboard clicking)"))
        XCTAssertTrue(TranscriptionPipelineSupport.looksLikeSoundAnnotation("[BLANK_AUDIO]"))
        XCTAssertTrue(TranscriptionPipelineSupport.looksLikeSoundAnnotation("[Typewriter sounds]"))
        XCTAssertTrue(TranscriptionPipelineSupport.looksLikeHallucination("(camera clicks)"))
        XCTAssertFalse(TranscriptionPipelineSupport.looksLikeSoundAnnotation("observations on the offshore industry"))
    }

    func testShouldAppendFinalSegmentRejectsHallucinationsAndDuplicates() {
        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldAppendFinalSegment(
                text: "Okay.",
                speakerLabel: "System",
                lastFinalText: nil
            )
        )
        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldAppendFinalSegment(
                text: "Same line.",
                speakerLabel: "System",
                lastFinalText: "Same line."
            )
        )
        XCTAssertTrue(
            TranscriptionPipelineSupport.shouldAppendFinalSegment(
                text: "Next sentence.",
                speakerLabel: "System",
                lastFinalText: "Previous sentence."
            )
        )
    }

    func testShouldAppendFinalSegmentRejectsMicEchoOfSystem() {
        let systemLines = [
            "observations on the",
            "state of the offshore",
            "or industry in India."
        ]

        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldAppendFinalSegment(
                text: "the state of the",
                speakerLabel: "You",
                lastFinalText: nil,
                recentOtherSpeakerTexts: systemLines,
                sourceMode: .mixed
            )
        )
        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldAppendFinalSegment(
                text: "offshore industry in India.",
                speakerLabel: "You",
                lastFinalText: nil,
                recentOtherSpeakerTexts: systemLines,
                sourceMode: .mixed
            )
        )
        XCTAssertTrue(
            TranscriptionPipelineSupport.shouldAppendFinalSegment(
                text: "I have a question about the budget.",
                speakerLabel: "You",
                lastFinalText: nil,
                recentOtherSpeakerTexts: systemLines,
                sourceMode: .mixed
            )
        )
    }

    func testShouldSkipEchoBleedOnlyForMixedMicInput() {
        XCTAssertTrue(
            TranscriptionPipelineSupport.shouldSkipEchoBleed(
                speakerLabel: "You",
                sourceMode: .mixed,
                micEnergy: 0.005,
                systemReferenceEnergy: 0.01,
                microphoneInputKind: .builtIn
            )
        )
        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldSkipEchoBleed(
                speakerLabel: "You",
                sourceMode: .mixed,
                micEnergy: 0.03,
                systemReferenceEnergy: 0.01,
                microphoneInputKind: .builtIn
            )
        )
        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldSkipEchoBleed(
                speakerLabel: "You",
                sourceMode: .mixed,
                micEnergy: 0.04,
                systemReferenceEnergy: 0.05,
                microphoneInputKind: .external
            )
        )
        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldSkipEchoBleed(
                speakerLabel: "You",
                sourceMode: .mixed,
                micEnergy: 0.025,
                systemReferenceEnergy: 0.04,
                microphoneInputKind: .builtIn
            )
        )
        XCTAssertTrue(
            TranscriptionPipelineSupport.shouldSkipEchoBleed(
                speakerLabel: "You",
                sourceMode: .mixed,
                micEnergy: 0.015,
                systemReferenceEnergy: 0.04,
                microphoneInputKind: .builtIn
            )
        )
        XCTAssertTrue(
            TranscriptionPipelineSupport.shouldSkipEchoBleed(
                speakerLabel: "You",
                sourceMode: .mixed,
                micEnergy: 0.01,
                systemReferenceEnergy: 0.05,
                microphoneInputKind: .external
            )
        )
        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldSkipEchoBleed(
                speakerLabel: "System",
                sourceMode: .mixed,
                micEnergy: 0.005,
                systemReferenceEnergy: 0.01
            )
        )
        XCTAssertFalse(
            TranscriptionPipelineSupport.shouldSkipEchoBleed(
                speakerLabel: "You",
                sourceMode: .mic,
                micEnergy: 0.005,
                systemReferenceEnergy: 0.01
            )
        )
    }

    func testChunkPipelineProducesSingleOrderedLinePerChunk() {
        var buffer = Array(repeating: Float(0.2), count: 96_000)
        var lines: [String] = []

        while let slice = TranscriptionPipelineSupport.popAudioSlice(
            from: &buffer,
            chunkSize: 32_000
        ) {
            let energy = TranscriptionPipelineSupport.rms(slice)
            guard TranscriptionPipelineSupport.shouldTranscribeSlice(energy: energy) else { continue }
            let chunkText = "chunk-\(lines.count + 1)"
            guard TranscriptionPipelineSupport.shouldAppendFinalSegment(
                text: chunkText,
                speakerLabel: "System",
                lastFinalText: lines.last
            ) else { continue }
            lines.append(chunkText)
        }

        XCTAssertEqual(lines, ["chunk-1", "chunk-2", "chunk-3"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testAppendDraftTextBuildsEnglishSentence() {
        let merged = TranscriptionPipelineSupport.appendDraftText(
            existing: "We need to finish",
            newSlice: "finish the report"
        )
        XCTAssertEqual(merged, "We need to finish the report")
    }

    func testAppendDraftTextBuildsChineseSentence() {
        let merged = TranscriptionPipelineSupport.appendDraftText(
            existing: "我们需要",
            newSlice: "完报告"
        )
        XCTAssertEqual(merged, "我们需要完报告")
    }
}
