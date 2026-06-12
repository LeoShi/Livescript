import XCTest
@testable import LivescriptCore

final class SenseVoiceTextCleanerTests: XCTestCase {
    func testStripsMetadataTags() {
        let cleaned = SenseVoiceTextCleaner.clean("<|en|><|NEUTRAL|><|Speech|>Hello team")
        XCTAssertEqual(cleaned, "Hello team")
    }

    func testReturnsEmptyForPunctuationOnlyOutput() {
        XCTAssertEqual(SenseVoiceTextCleaner.clean("."), "")
        XCTAssertEqual(SenseVoiceTextCleaner.clean("<|nospeech|>"), "")
    }
}
