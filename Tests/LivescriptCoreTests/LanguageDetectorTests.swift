import XCTest
@testable import LivescriptCore

final class LanguageDetectorTests: XCTestCase {
    func testDetectEnglish() {
        XCTAssertEqual(LanguageDetector.detect(from: "Hello world"), .english)
    }

    func testDetectChinese() {
        XCTAssertEqual(LanguageDetector.detect(from: "你好世界"), .chinese)
    }

    func testDetectMixed() {
        XCTAssertEqual(LanguageDetector.detect(from: "Hello 世界"), .mixed)
    }

    func testWhisperLanguageCodeEnglish() {
        XCTAssertEqual(LanguageDetector.whisperLanguageCode(from: "Meeting notes"), "en")
    }

    func testWhisperLanguageCodeChinese() {
        XCTAssertEqual(LanguageDetector.whisperLanguageCode(from: "我们需要完成报告"), "zh")
    }

    func testWhisperLanguageCodeMixedUsesDominantScript() {
        XCTAssertEqual(LanguageDetector.whisperLanguageCode(from: "你好世界 hi"), "zh")
        XCTAssertEqual(LanguageDetector.whisperLanguageCode(from: "Hello world 你"), "en")
    }

    func testShouldRefineWithEnglishWhisperOnlyForEnglishDraft() {
        XCTAssertTrue(LanguageDetector.shouldRefineWithEnglishWhisper(draftHint: "finish the report"))
        XCTAssertFalse(LanguageDetector.shouldRefineWithEnglishWhisper(draftHint: "完成报告"))
        XCTAssertFalse(LanguageDetector.shouldRefineWithEnglishWhisper(draftHint: nil))
    }
}
