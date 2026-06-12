import Foundation

enum SenseVoiceTextCleaner {
    /// Removes SenseVoice metadata/event tags and normalizes whitespace.
    nonisolated static func clean(_ text: String) -> String {
        var cleaned = text

        while let range = cleaned.range(of: "<\\|[^|]+\\|>", options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        cleaned = cleaned
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty || TranscriptionPipelineSupport.meaningfulContent(from: cleaned).isEmpty {
            return ""
        }

        return cleaned
    }
}
