import Foundation

enum UtteranceTranscriptionPipeline {
    static func shouldPublishDraft(
        text: String,
        speakerLabel: String,
        sourceMode: TranscriptSourceMode
    ) -> Bool {
        let normalized = TranscriptionPipelineSupport.normalizeTranscriptText(text)
        guard !normalized.isEmpty else { return false }
        guard !TranscriptionPipelineSupport.looksLikeHallucination(normalized) else { return false }
        guard !TranscriptionPipelineSupport.looksLikeFragmentHallucination(normalized) else { return false }
        return true
    }

    static func shouldPublishRefined(
        text: String,
        speakerLabel: String,
        lastFinalText: String?,
        recentOtherSpeakerTexts: [String],
        sourceMode: TranscriptSourceMode
    ) -> Bool {
        TranscriptionPipelineSupport.shouldAppendFinalSegment(
            text: text,
            speakerLabel: speakerLabel,
            lastFinalText: lastFinalText,
            recentOtherSpeakerTexts: recentOtherSpeakerTexts,
            sourceMode: sourceMode
        )
    }
}
