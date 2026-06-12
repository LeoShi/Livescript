import XCTest
@testable import LivescriptCore

final class UtteranceTranscriptionPipelineTests: XCTestCase {
    func testDraftAllowsShortButNotEmptyText() {
        XCTAssertTrue(
            UtteranceTranscriptionPipeline.shouldPublishDraft(
                text: "Hello team",
                speakerLabel: "System",
                sourceMode: .mixed
            )
        )
        XCTAssertFalse(
            UtteranceTranscriptionPipeline.shouldPublishDraft(
                text: "我。",
                speakerLabel: "You",
                sourceMode: .mixed
            )
        )
    }
}
