import Foundation

enum LanguageDetector {
    static func detect(from text: String) -> TranscriptLanguage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        var chineseCount = 0
        var englishCount = 0

        for scalar in trimmed.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) {
                chineseCount += 1
            } else if CharacterSet.letters.contains(scalar), scalar.isASCII {
                englishCount += 1
            }
        }

        if chineseCount > 0, englishCount > 0 { return .mixed }
        if chineseCount > 0 { return .chinese }
        if englishCount > 0 { return .english }
        return .unknown
    }
}
