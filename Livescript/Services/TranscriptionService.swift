import Foundation

protocol TranscriptionService: Actor {
    func configure(localModelFolder: String?, speedProfileRawValue: String) async
    func prepareIfNeeded(statusHandler: ((ModelPreparationStatus) -> Void)?) async throws
    func transcribe(
        audio: [Float],
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> String
    func transcribeDraft(
        audio: [Float],
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> String
    func transcribeRefine(
        audio: [Float],
        draftHint: String?,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> String
    func polishRefinedText(_ text: String) async -> String
    func chunkHasSpeech(_ chunk: [Float], minimumEnergy: Float) async -> Bool
    func resetVoiceActivity() async
    var usesSmartCaptions: Bool { get async }
}

actor LivescriptTranscriptionService: TranscriptionService {
    private let whisper = WhisperTranscriber()
    private let refineWhisper = WhisperTranscriber(
        fallbackModelName: TranscriptionSpeedProfile.refineWhisperModelVariant
    )
    private let senseVoice = SenseVoiceTranscriber()
    private let punctuation = PunctuationService()
    private let voiceActivity = VoiceActivityDetector()
    private var smartCaptionsEnabled = true
    private var engine: TranscriptionEngine = .senseVoice

    var usesSmartCaptions: Bool {
        smartCaptionsEnabled
    }

    func configure(localModelFolder: String?, speedProfileRawValue: String) async {
        smartCaptionsEnabled = TranscriptionSpeedProfile.usesSmartCaptions(for: speedProfileRawValue)
        engine = TranscriptionSpeedProfile.engine(for: speedProfileRawValue)

        await senseVoice.configure(localModelFolder: localModelFolder)
        await punctuation.configure(localModelFolder: localModelFolder)
        await voiceActivity.configure(localModelFolder: localModelFolder)

        if smartCaptionsEnabled {
            await refineWhisper.configure(
                localModelFolder: localModelFolder,
                fallbackModelName: TranscriptionSpeedProfile.refineWhisperModelVariant,
                usesStrictDecodeThresholds: false
            )
        }

        if !smartCaptionsEnabled {
            let whisperVariant = TranscriptionSpeedProfile.whisperModelVariant(for: speedProfileRawValue)
            let usesStrict = TranscriptionSpeedProfile.usesStrictDecode(for: speedProfileRawValue)
            await whisper.configure(
                localModelFolder: localModelFolder,
                fallbackModelName: whisperVariant,
                usesStrictDecodeThresholds: usesStrict
            )
        }
    }

    func prepareIfNeeded(statusHandler: ((ModelPreparationStatus) -> Void)? = nil) async throws {
        if smartCaptionsEnabled {
            statusHandler?(ModelPreparationStatus(message: "Loading SenseVoice-Small (draft)...", progress: nil))
            try await senseVoice.prepareIfNeeded(statusHandler: statusHandler)

            statusHandler?(ModelPreparationStatus(
                message: "Loading distil-large-v3 (refine)...",
                progress: nil
            ))
            try await refineWhisper.prepareIfNeeded(statusHandler: statusHandler)

            statusHandler?(ModelPreparationStatus(message: "Loading VAD model (optional)...", progress: nil))
            await voiceActivity.prepareIfNeeded()

            statusHandler?(ModelPreparationStatus(message: "Loading punctuation model (optional)...", progress: nil))
            try await punctuation.prepareIfNeeded()
            statusHandler?(ModelPreparationStatus(message: "Smart captions ready", progress: 1.0))
            return
        }

        switch engine {
        case .whisper:
            try await whisper.prepareIfNeeded(statusHandler: statusHandler)
        case .senseVoice:
            try await senseVoice.prepareIfNeeded(statusHandler: statusHandler)
        }
    }

    func transcribe(
        audio: [Float],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        if smartCaptionsEnabled {
            return try await transcribeDraft(audio: audio, onProgress: onProgress)
        }
        switch engine {
        case .whisper:
            return try await whisper.transcribe(audio: audio, onProgress: onProgress)
        case .senseVoice:
            return try await senseVoice.transcribe(audio: audio, onProgress: onProgress)
        }
    }

    func transcribeDraft(
        audio: [Float],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await senseVoice.transcribe(audio: audio, onProgress: onProgress)
    }

    func transcribeRefine(
        audio: [Float],
        draftHint: String?,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        if LanguageDetector.shouldRefineWithEnglishWhisper(draftHint: draftHint) {
            return try await refineWhisper.transcribe(
                audio: audio,
                language: LanguageDetector.englishWhisperCode,
                onProgress: onProgress
            )
        }
        return try await senseVoice.transcribe(audio: audio, onProgress: onProgress)
    }

    func polishRefinedText(_ text: String) async -> String {
        guard LanguageDetector.whisperLanguageCode(from: text) != LanguageDetector.chineseWhisperCode else {
            return text
        }
        return await punctuation.addPunctuation(to: text)
    }

    func chunkHasSpeech(_ chunk: [Float], minimumEnergy: Float) async -> Bool {
        if await voiceActivity.isAvailable {
            return await voiceActivity.isSpeech(in: chunk)
        }
        return TranscriptionPipelineSupport.rms(chunk) >= minimumEnergy
    }

    func resetVoiceActivity() async {
        await voiceActivity.reset()
    }
}
