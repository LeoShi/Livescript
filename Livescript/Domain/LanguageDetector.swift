import Foundation

enum LanguageDetector {
    /// Supported refine languages for Whisper (English-only distil-large-v3).
    static let englishWhisperCode = "en"
    static let chineseWhisperCode = "zh"

    static func detect(from text: String) -> TranscriptLanguage {
        let counts = scriptCounts(in: text)
        guard counts.chinese > 0 || counts.english > 0 else { return .unknown }
        if counts.chinese > 0, counts.english > 0 { return .mixed }
        if counts.chinese > 0 { return .chinese }
        return .english
    }

    /// Returns `en` or `zh` when the text contains supported script; nil when unknown.
    static func whisperLanguageCode(from text: String) -> String? {
        let counts = scriptCounts(in: text)
        guard counts.chinese > 0 || counts.english > 0 else { return nil }
        if counts.chinese > 0, counts.english > 0 {
            return counts.chinese >= counts.english ? chineseWhisperCode : englishWhisperCode
        }
        if counts.chinese > 0 { return chineseWhisperCode }
        return englishWhisperCode
    }

    static func shouldRefineWithEnglishWhisper(draftHint: String?) -> Bool {
        whisperLanguageCode(from: draftHint ?? "") == englishWhisperCode
    }

    private static func scriptCounts(in text: String) -> (chinese: Int, english: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0) }

        var chineseCount = 0
        var englishCount = 0

        for scalar in trimmed.unicodeScalars {
            if isCJK(scalar) {
                chineseCount += 1
            } else if CharacterSet.letters.contains(scalar), scalar.isASCII {
                englishCount += 1
            }
        }

        return (chineseCount, englishCount)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
    }
}
