import Foundation

enum TranscriptionPipelineSupport {
    static let defaultMinimumEnergy: Float = 0.004

    /// Pops a fixed-size, non-overlapping window from the front of the buffer.
    static func popAudioSlice(from buffer: inout [Float], chunkSize: Int) -> [Float]? {
        guard buffer.count >= chunkSize else { return nil }
        let audioSlice = Array(buffer.prefix(chunkSize))
        buffer.removeFirst(chunkSize)
        return audioSlice
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for value in samples { sum += value * value }
        return sqrt(sum / Float(samples.count))
    }

    static func shouldTranscribeSlice(
        energy: Float,
        minimumEnergy: Float = defaultMinimumEnergy
    ) -> Bool {
        energy >= minimumEnergy
    }

    static func shouldSkipEchoBleed(
        speakerLabel: String,
        sourceMode: TranscriptSourceMode,
        micEnergy: Float,
        systemReferenceEnergy: Float,
        microphoneInputKind: AudioInputKind = .unknown
    ) -> Bool {
        guard speakerLabel == "You", sourceMode == .mixed else { return false }
        guard systemReferenceEnergy > 0.003 else { return false }

        // Clear local speech — applies to both built-in and headset mics.
        if micEnergy >= 0.02 { return false }

        switch microphoneInputKind {
        case .external:
            // Headsets rarely pick up speaker bleed; only skip very quiet correlated chunks.
            if micEnergy > systemReferenceEnergy { return false }
            return micEnergy <= systemReferenceEnergy * 1.1

        case .builtIn, .unknown:
            // Built-in mic: skip when energy tracks system audio (open-speaker bleed).
            let ratio = micEnergy / systemReferenceEnergy
            return ratio >= 0.35 && ratio <= 1.1
        }
    }

    static func normalizeTranscriptText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Merges a fast incremental draft slice into the running utterance text.
    static func appendDraftText(existing: String, newSlice: String) -> String {
        let existing = normalizeTranscriptText(existing)
        let newSlice = normalizeTranscriptText(newSlice)
        guard !newSlice.isEmpty else { return existing }
        guard !existing.isEmpty else { return newSlice }

        if newSlice == existing { return existing }
        if existing.hasSuffix(newSlice) { return existing }
        if newSlice.hasPrefix(existing) { return newSlice }

        if let overlap = longestSuffixPrefixOverlap(existing, newSlice), overlap.count >= 1 {
            return existing + String(newSlice.dropFirst(overlap.count))
        }

        if shouldInsertSpaceBetween(existing, newSlice) {
            return existing + " " + newSlice
        }
        return existing + newSlice
    }

    private static func longestSuffixPrefixOverlap(_ left: String, _ right: String) -> String? {
        let maxLength = min(left.count, right.count)
        guard maxLength > 0 else { return nil }
        for length in stride(from: maxLength, through: 1, by: -1) {
            if left.suffix(length) == right.prefix(length) {
                return String(left.suffix(length))
            }
        }
        return nil
    }

    private static func shouldInsertSpaceBetween(_ left: String, _ right: String) -> Bool {
        guard let last = left.unicodeScalars.last,
              let first = right.unicodeScalars.first else {
            return false
        }
        return CharacterSet.letters.contains(last)
            && CharacterSet.letters.contains(first)
            && last.isASCII
            && first.isASCII
    }

    static func looksLikeSoundAnnotation(_ text: String) -> Bool {
        let trimmed = normalizeTranscriptText(text)
        guard !trimmed.isEmpty else { return false }

        if isWrappedIn(trimmed, start: "(", end: ")") { return true }
        if isWrappedIn(trimmed, start: "[", end: "]") { return true }

        let lower = trimmed.lowercased()
        let noiseMarkers = [
            "blank_audio",
            "blank audio",
            "keyboard clicking",
            "keyboard clacking",
            "keyboard typing",
            "typewriter",
            "camera click",
            "camera clicks",
            "applause",
            "laughter",
            "music playing",
            "silence",
            "inaudible",
            "background noise",
            "static",
            "beep",
            "ding"
        ]
        return noiseMarkers.contains(where: { lower.contains($0) })
    }

    static func looksLikeHallucination(_ text: String) -> Bool {
        if looksLikeSoundAnnotation(text) { return true }
        if looksLikeFragmentHallucination(text) { return true }

        let normalized = normalizeTranscriptText(text).lowercased()
        let blocked = [
            "thank you.",
            "thank you",
            "thanks for watching",
            "okay.",
            "okay",
            "ok.",
            "ok",
            "yeah.",
            "yeah",
            "um.",
            "um",
            "hmm.",
            "hmm",
            "字幕由 amara.org 社群提供",
            "字幕由amra.org社群提供"
        ]
        return blocked.contains(normalized)
    }

    /// SenseVoice/Whisper often emit 1–2 character fragments on near-silent chunks.
    static func looksLikeFragmentHallucination(_ text: String) -> Bool {
        let normalized = normalizeTranscriptText(text)
        guard !normalized.isEmpty else { return false }

        let content = meaningfulContent(from: normalized)
        if content.isEmpty { return true }

        if content.count <= 2 { return true }

        let fillerPatterns = ["嗯嗯", "啊啊", "呃呃", "哦哦", "唉唉"]
        if fillerPatterns.contains(content) { return true }

        return false
    }

    static func meaningfulContent(from text: String) -> String {
        String(
            text.filter { character in
                guard !character.isWhitespace else { return false }
                return !isPunctuation(character)
            }
        )
    }

    /// Prevents consecutive duplicate lines from repeated silent decode passes.
    static func isDuplicateOfLastFinalSegment(_ text: String, lastFinalText: String?) -> Bool {
        let candidate = normalizeTranscriptText(text)
        guard !candidate.isEmpty else { return true }
        guard let lastFinalText else { return false }
        let previous = normalizeTranscriptText(lastFinalText)
        guard !previous.isEmpty else { return false }
        if candidate == previous { return true }
        return isNearDuplicateShortFragment(candidate, lastFinalText: previous)
    }

    /// Catches repeated micro-fragments like "我。" → "我." → "我斑。" on silent audio.
    static func isNearDuplicateShortFragment(_ text: String, lastFinalText: String) -> Bool {
        let current = meaningfulContent(from: text)
        let previous = meaningfulContent(from: lastFinalText)
        guard !current.isEmpty, !previous.isEmpty else { return false }
        guard current.count <= 4, previous.count <= 4 else { return false }

        if current == previous { return true }
        if current.contains(previous) || previous.contains(current) { return true }

        if current.count <= 2, previous.count <= 2,
           current.first == previous.first {
            return true
        }

        return false
    }

    /// Detects when the mic picked up the same meeting audio already captured on System.
    static func isEchoOfOtherSpeaker(
        _ text: String,
        otherSpeakerRecentTexts: [String]
    ) -> Bool {
        let candidate = normalizeTranscriptText(text).lowercased()
        guard candidate.count >= 8 else { return false }

        let candidateWords = significantWords(in: candidate)
        guard candidateWords.count >= 2 else { return false }

        for other in otherSpeakerRecentTexts {
            let otherNormalized = normalizeTranscriptText(other).lowercased()
            guard !otherNormalized.isEmpty else { continue }

            if candidate.contains(otherNormalized) || otherNormalized.contains(candidate) {
                return true
            }

            let otherWords = significantWords(in: otherNormalized)
            guard !otherWords.isEmpty else { continue }

            let shared = candidateWords.intersection(otherWords)
            let overlapRatio = Float(shared.count) / Float(candidateWords.count)
            if overlapRatio >= 0.45 {
                return true
            }
        }

        return false
    }

    static func shouldAppendFinalSegment(
        text: String,
        speakerLabel: String,
        lastFinalText: String?,
        recentOtherSpeakerTexts: [String] = [],
        sourceMode: TranscriptSourceMode = .mic
    ) -> Bool {
        let normalized = normalizeTranscriptText(text)
        guard !normalized.isEmpty else { return false }
        guard !looksLikeHallucination(normalized) else { return false }
        guard !isDuplicateOfLastFinalSegment(normalized, lastFinalText: lastFinalText) else { return false }

        if speakerLabel == "You", sourceMode == .mixed, !recentOtherSpeakerTexts.isEmpty {
            guard !isEchoOfOtherSpeaker(normalized, otherSpeakerRecentTexts: recentOtherSpeakerTexts) else {
                return false
            }
        }

        return true
    }

    private static func isWrappedIn(_ text: String, start: Character, end: Character) -> Bool {
        text.hasPrefix(String(start)) && text.hasSuffix(String(end))
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        if character.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
            return true
        }
        return "。，、；：？！…．·“”‘’（）【】《》".contains(character)
    }

    private static func significantWords(in text: String) -> Set<String> {
        Set(
            text
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count > 2 }
        )
    }
}
