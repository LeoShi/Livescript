import AppKit
import Combine
import Foundation

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var sourceMode: TranscriptSourceMode = .mixed
    @Published var isRunning = false
    @Published var isStealthEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "StealthEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "StealthEnabled")
    }() {
        didSet {
            UserDefaults.standard.set(isStealthEnabled, forKey: "StealthEnabled")
        }
    }
    @Published var statusMessage = "Idle"
    @Published var systemCaptureStatus = "System audio: idle"
    @Published var segments: [TranscriptSegment] = []
    @Published var elapsedText = "00:00:00"
    @Published var modelFolderPath: String = {
        let stored = UserDefaults.standard.string(forKey: "ModelFolderPath") ?? ""
        if !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        return ModelStoragePaths.defaultModelsDirectory
    }()
    @Published var modelPreparationMessage = "Model not prepared"
    @Published var modelDownloadProgress: Double?
    @Published var transcriptIsSelectable = true
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0
    @Published var speedProfile: TranscriptionSpeedProfile = {
        let stored = UserDefaults.standard.string(forKey: "TranscriptionSpeedProfile") ?? ""
        if stored == "realtime" { return .smart }
        return TranscriptionSpeedProfile(rawValue: stored) ?? .smart
    }() {
        didSet {
            UserDefaults.standard.set(speedProfile.rawValue, forKey: "TranscriptionSpeedProfile")
            Task {
                await applySpeedProfile()
            }
        }
    }

    private var session: TranscriptSession?
    private var micBuffer: [Float] = []
    private var systemBuffer: [Float] = []
    private var startedAt: Date?
    private var timer: Timer?
    private var lastChunkSaveAt: Date = .distantPast
    private var lastSystemChunkAt: Date = .distantPast
    private var recentSystemEnergy: Float = 0

    private let micQueue = TranscriptionWorkQueue()
    private let systemQueue = TranscriptionWorkQueue()
    private var micUtterance = SpeakerUtteranceState(
        minimumEnergy: 0.0035,
        draftHopSeconds: 1.0,
        maxUtteranceSeconds: 8
    )
    private var systemUtterance = SpeakerUtteranceState(
        minimumEnergy: 0.0035,
        draftHopSeconds: 1.0,
        maxUtteranceSeconds: 8
    )

    private let capture = AudioCaptureCoordinator()
    private let transcriber = LivescriptTranscriptionService()
    private let speakerDiarizer = SpeakerDiarizer()
    private var store: SessionStore?

    init() {
        Task { await applySpeedProfile() }
    }

    func start() async {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Folder for Session Data"
        panel.canCreateDirectories = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let base = panel.url else {
            statusMessage = "Start canceled. Please choose a folder for session files."
            return
        }

        let dir = base.appendingPathComponent("MeetingSession_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        store = SessionStore(baseDirectory: dir)
        await applySpeedProfile()
        await speakerDiarizer.configure(
            downloadBaseFolder: modelFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try await transcriber.prepareIfNeeded { status in
                Task { @MainActor in
                    self.modelPreparationMessage = status.message
                    self.modelDownloadProgress = status.progress
                }
            }
        } catch {
            statusMessage = "Model setup failed. Check your model folder or network, then try again."
            modelPreparationMessage = "Model setup failed"
            modelDownloadProgress = nil
            return
        }

        session = TranscriptSession(
            id: UUID(),
            startedAt: Date(),
            endedAt: nil,
            sourceMode: sourceMode,
            segments: []
        )
        startedAt = Date()
        elapsedText = "00:00:00"
        statusMessage = "Starting..."
        modelDownloadProgress = nil
        segments = []
        micBuffer = []
        systemBuffer = []
        micQueue.reset()
        systemQueue.reset()
        resetUtteranceStates()
        lastChunkSaveAt = .distantPast
        lastSystemChunkAt = .distantPast
        recentSystemEnergy = 0
        micLevel = 0
        systemLevel = 0
        systemCaptureStatus = sourceMode == .mic ? "System audio: not used" : "System audio: starting…"

        capture.onChunk = { [weak self] chunk in
            Task { @MainActor in
                self?.consume(chunk)
            }
        }
        capture.onSystemStatus = { [weak self] status in
            Task { @MainActor in
                self?.applySystemStatus(status)
            }
        }

        do {
            try capture.start(sourceMode: sourceMode)
            isRunning = true
            startTimer()
            statusMessage = "Live transcription running (\(speedProfile.displayName), \(speedProfile.expectedLatencySeconds))."
        } catch {
            statusMessage = "Audio capture failed to start. Check microphone/screen recording permissions."
        }
    }

    func chooseModelFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose WhisperKit Model Folder"
        panel.canCreateDirectories = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        modelFolderPath = folder.path
        UserDefaults.standard.set(modelFolderPath, forKey: "ModelFolderPath")
        statusMessage = "Model folder saved. Livescript will use local models first."
        modelPreparationMessage = "Model folder updated"
        modelDownloadProgress = nil
    }

    func clearModelFolder() {
        modelFolderPath = ""
        UserDefaults.standard.removeObject(forKey: "ModelFolderPath")
        statusMessage = "Model folder cleared. Livescript will download/use fallback models."
        modelPreparationMessage = "Model folder cleared"
        modelDownloadProgress = nil
    }

    func stop() {
        guard isRunning else { return }
        if speedProfile.usesSmartCaptions {
            flushUtteranceOnStop(state: micUtterance, speakerLabel: "You")
            flushUtteranceOnStop(state: systemUtterance, speakerLabel: "System")
        }
        capture.stop()
        stopTimer()
        isRunning = false
        statusMessage = "Stopped."
        systemCaptureStatus = "System audio: idle"
        micLevel = 0
        systemLevel = 0
        segments.removeAll { $0.phase == .draft || $0.phase == .refining }
        micQueue.reset()
        systemQueue.reset()
        resetUtteranceStates()

        if var session {
            session.endedAt = Date()
            self.session = session
            Task {
                try? await store?.saveCheckpoint(session)
            }
        }
    }

    func export(format: TranscriptExportFormat) {
        guard let session else { return }
        let panel = NSSavePanel()
        panel.title = "Export Transcript"
        panel.nameFieldStringValue = TranscriptExporter.fileName(for: session, format: format)
        panel.allowedContentTypes = TranscriptExporter.suggestedTypes(for: format)

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            statusMessage = "Export canceled."
            return
        }

        do {
            let content = TranscriptExporter.render(session: session, format: format)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            statusMessage = "Exported to \(fileURL.lastPathComponent)"
        } catch {
            statusMessage = "Export failed. Please choose another location and try again."
        }
    }

    private func applySystemStatus(_ status: SystemCaptureStatus) {
        switch status {
        case .notStarted:
            systemCaptureStatus = sourceMode == .mic ? "System audio: not used" : "System audio: idle"
        case .starting:
            systemCaptureStatus = "System audio: starting…"
        case .running:
            systemCaptureStatus = "System audio: running"
        case .denied(let message):
            systemCaptureStatus = "System audio: denied — \(message)"
        case .error(let message):
            systemCaptureStatus = "System audio: error — \(message)"
        }
    }

    private func consume(_ chunk: CapturedAudioChunk) {
        guard isRunning else { return }
        switch chunk.source {
        case .mic:
            micLevel = TranscriptionPipelineSupport.rms(chunk.samples)
            guard sourceMode == .mic || sourceMode == .mixed else { return }
            if speedProfile.usesSmartCaptions {
                applySmartCaptionIngest(
                    chunk.samples,
                    state: micUtterance,
                    speakerLabel: "You"
                )
            } else {
                micBuffer.append(contentsOf: chunk.samples)
                enqueueReadySlices(from: &micBuffer, queue: micQueue, speakerLabel: "You")
            }
        case .system:
            let energy = TranscriptionPipelineSupport.rms(chunk.samples)
            systemLevel = energy
            recentSystemEnergy = max(energy, recentSystemEnergy * 0.85)
            lastSystemChunkAt = Date()
            guard sourceMode == .system || sourceMode == .mixed else { return }
            if speedProfile.usesSmartCaptions {
                applySmartCaptionIngest(
                    chunk.samples,
                    state: systemUtterance,
                    speakerLabel: "System"
                )
            } else {
                systemBuffer.append(contentsOf: chunk.samples)
                enqueueReadySlices(from: &systemBuffer, queue: systemQueue, speakerLabel: "System")
            }
        }
    }

    private func resetUtteranceStates() {
        micUtterance.reset(
            minimumEnergy: speedProfile.minimumEnergy,
            draftHopSeconds: speedProfile.draftHopSeconds,
            maxUtteranceSeconds: speedProfile.maxUtteranceSeconds
        )
        systemUtterance.reset(
            minimumEnergy: speedProfile.minimumEnergy,
            draftHopSeconds: speedProfile.draftHopSeconds,
            maxUtteranceSeconds: speedProfile.maxUtteranceSeconds
        )
    }

    private func applySmartCaptionIngest(
        _ samples: [Float],
        state: SpeakerUtteranceState,
        speakerLabel: String
    ) {
        let energy = TranscriptionPipelineSupport.rms(samples)
        if TranscriptionPipelineSupport.shouldSkipEchoBleed(
            speakerLabel: speakerLabel,
            sourceMode: sourceMode,
            micEnergy: energy,
            systemReferenceEnergy: max(recentSystemEnergy, systemLevel),
            microphoneInputKind: capture.microphoneInputKind
        ) {
            return
        }

        let events = state.buffer.append(samples)
        for event in events {
            switch event {
            case .draftHop(let audio):
                state.pendingDrafts = [audio]
                processDraftQueue(state: state, speakerLabel: speakerLabel)
            case .utteranceComplete(let audio):
                let completedUtteranceID = state.utteranceID
                state.pendingRefines = [(audio: audio, utteranceID: completedUtteranceID)]
                state.accumulatedDraftText = ""
                state.utteranceID = UUID()
                Task { await transcriber.resetVoiceActivity() }
                processRefineQueue(state: state, speakerLabel: speakerLabel)
            }
        }
    }

    private func flushUtteranceOnStop(state: SpeakerUtteranceState, speakerLabel: String) {
        guard let audio = state.buffer.flushPendingUtterance() else { return }
        state.pendingRefines = [(audio: audio, utteranceID: state.utteranceID)]
        processRefineQueue(state: state, speakerLabel: speakerLabel)
    }

    private func processDraftQueue(state: SpeakerUtteranceState, speakerLabel: String) {
        guard !state.isDraftDecoding else { return }
        guard !state.pendingDrafts.isEmpty else { return }

        let audio = state.pendingDrafts.removeFirst()
        let energy = TranscriptionPipelineSupport.rms(audio)
        guard TranscriptionPipelineSupport.shouldTranscribeSlice(
            energy: energy,
            minimumEnergy: speedProfile.minimumEnergy
        ) else {
            processDraftQueue(state: state, speakerLabel: speakerLabel)
            return
        }

        state.isDraftDecoding = true
        let utteranceID = state.utteranceID
        let transcriber = self.transcriber

        Task {
            do {
                let text = try await transcriber.transcribeDraft(audio: audio) { partial in
                    Task { @MainActor in
                        self.publishAccumulatedDraft(
                            sliceText: partial,
                            state: state,
                            speakerLabel: speakerLabel,
                            utteranceID: utteranceID
                        )
                    }
                }
                await MainActor.run {
                    self.finishDraft(
                        text: text,
                        state: state,
                        speakerLabel: speakerLabel,
                        utteranceID: utteranceID
                    )
                }
            } catch {
                await MainActor.run {
                    state.isDraftDecoding = false
                    self.statusMessage = "Draft error: \(error.localizedDescription)"
                    self.processDraftQueue(state: state, speakerLabel: speakerLabel)
                }
            }
        }
    }

    private func finishDraft(
        text: String,
        state: SpeakerUtteranceState,
        speakerLabel: String,
        utteranceID: UUID
    ) {
        let hasNewerDraft = !state.pendingDrafts.isEmpty
        if !hasNewerDraft {
            publishAccumulatedDraft(
                sliceText: text,
                state: state,
                speakerLabel: speakerLabel,
                utteranceID: utteranceID
            )
        }
        state.isDraftDecoding = false
        processDraftQueue(state: state, speakerLabel: speakerLabel)
    }

    private func publishAccumulatedDraft(
        sliceText: String,
        state: SpeakerUtteranceState,
        speakerLabel: String,
        utteranceID: UUID,
        phase: TranscriptSegmentPhase = .draft
    ) {
        let normalized = TranscriptionPipelineSupport.normalizeTranscriptText(sliceText)
        guard UtteranceTranscriptionPipeline.shouldPublishDraft(
            text: normalized,
            speakerLabel: speakerLabel,
            sourceMode: sourceMode
        ) else { return }

        if phase == .draft {
            state.accumulatedDraftText = TranscriptionPipelineSupport.appendDraftText(
                existing: state.accumulatedDraftText,
                newSlice: normalized
            )
            updateDraftSegment(
                text: state.accumulatedDraftText,
                speakerLabel: speakerLabel,
                utteranceID: utteranceID,
                phase: phase
            )
        } else {
            updateDraftSegment(
                text: normalized,
                speakerLabel: speakerLabel,
                utteranceID: utteranceID,
                phase: phase
            )
        }
    }

    private func processRefineQueue(state: SpeakerUtteranceState, speakerLabel: String) {
        guard !state.isRefining else { return }
        guard !state.pendingRefines.isEmpty else { return }

        let refineJob = state.pendingRefines.removeFirst()
        let audio = refineJob.audio
        let utteranceID = refineJob.utteranceID
        let energy = TranscriptionPipelineSupport.rms(audio)
        guard TranscriptionPipelineSupport.shouldTranscribeSlice(
            energy: energy,
            minimumEnergy: speedProfile.minimumEnergy
        ) else {
            processRefineQueue(state: state, speakerLabel: speakerLabel)
            return
        }

        state.isRefining = true
        markUtteranceRefining(speakerLabel: speakerLabel, utteranceID: utteranceID)
        let draftHint = draftText(for: speakerLabel, utteranceID: utteranceID)
        statusMessage = "Refining \(speakerLabel)…"
        let transcriber = self.transcriber

        Task {
            do {
                let text = try await transcriber.transcribeRefine(
                    audio: audio,
                    draftHint: draftHint
                ) { partial in
                    Task { @MainActor in
                        guard self.isRunning else { return }
                        self.updateDraftSegment(
                            text: partial,
                            speakerLabel: speakerLabel,
                            utteranceID: utteranceID,
                            phase: .refining
                        )
                    }
                }
                let polished = await transcriber.polishRefinedText(text)
                await MainActor.run {
                    self.finishRefine(
                        text: polished,
                        state: state,
                        speakerLabel: speakerLabel,
                        utteranceID: utteranceID
                    )
                }
            } catch {
                await MainActor.run {
                    state.isRefining = false
                    self.statusMessage = "Refine error: \(error.localizedDescription)"
                    self.processRefineQueue(state: state, speakerLabel: speakerLabel)
                }
            }
        }
    }

    private func finishRefine(
        text: String,
        state: SpeakerUtteranceState,
        speakerLabel: String,
        utteranceID: UUID
    ) {
        let normalized = TranscriptionPipelineSupport.normalizeTranscriptText(text)
        let lastFinalText = lastFinalText(for: speakerLabel)
        let recentSystemTexts = speakerLabel == "You" ? recentFinalTexts(for: "System") : []

        if UtteranceTranscriptionPipeline.shouldPublishRefined(
            text: normalized,
            speakerLabel: speakerLabel,
            lastFinalText: lastFinalText,
            recentOtherSpeakerTexts: recentSystemTexts,
            sourceMode: sourceMode
        ) {
            replaceWithRefinedSegment(
                text: normalized,
                speakerLabel: speakerLabel,
                utteranceID: utteranceID
            )
            statusMessage = "Updated \(speakerLabel) caption."
        } else {
            removeUtteranceSegments(utteranceID: utteranceID, speakerLabel: speakerLabel)
            statusMessage = "Filtered \(speakerLabel) utterance."
        }

        state.isRefining = false
        if state.pendingRefines.count > 1 {
            state.pendingRefines = [state.pendingRefines[state.pendingRefines.count - 1]]
        }
        processRefineQueue(state: state, speakerLabel: speakerLabel)
    }

    private func draftText(for speakerLabel: String, utteranceID: UUID) -> String? {
        segments.last(where: {
            $0.utteranceID == utteranceID
                && $0.speakerLabel == speakerLabel
                && $0.phase != .refined
        })?.text
    }

    private func updateDraftSegment(
        text: String,
        speakerLabel: String,
        utteranceID: UUID,
        phase: TranscriptSegmentPhase = .draft
    ) {
        let trimmed = TranscriptionPipelineSupport.normalizeTranscriptText(text)
        guard UtteranceTranscriptionPipeline.shouldPublishDraft(
            text: trimmed,
            speakerLabel: speakerLabel,
            sourceMode: sourceMode
        ) else { return }

        if let index = segments.lastIndex(where: {
            $0.utteranceID == utteranceID && $0.speakerLabel == speakerLabel && $0.phase != .refined
        }) {
            var segment = segments[index]
            segment.text = trimmed
            segment.phase = phase
            segment.language = LanguageDetector.detect(from: trimmed)
            segments[index] = segment
        } else {
            let segment = TranscriptSegment(
                id: UUID(),
                timestamp: Date(),
                text: trimmed,
                isFinal: false,
                language: LanguageDetector.detect(from: trimmed),
                speakerLabel: speakerLabel,
                phase: phase,
                utteranceID: utteranceID
            )
            segments.append(segment)
        }
    }

    private func markUtteranceRefining(speakerLabel: String, utteranceID: UUID) {
        segments = segments.map { segment in
            guard segment.utteranceID == utteranceID,
                  segment.speakerLabel == speakerLabel,
                  segment.phase == .draft else {
                return segment
            }
            var updated = segment
            updated.phase = .refining
            return updated
        }
    }

    private func replaceWithRefinedSegment(
        text: String,
        speakerLabel: String,
        utteranceID: UUID
    ) {
        removeUtteranceSegments(utteranceID: utteranceID, speakerLabel: speakerLabel)
        appendFinalSegment(
            text,
            speakerLabel: speakerLabel,
            phase: .refined,
            utteranceID: utteranceID,
            revisedAt: Date()
        )
    }

    private func removeUtteranceSegments(utteranceID: UUID, speakerLabel: String) {
        segments.removeAll {
            $0.utteranceID == utteranceID && $0.speakerLabel == speakerLabel && $0.phase != .refined
        }
    }

    private func enqueueReadySlices(
        from buffer: inout [Float],
        queue: TranscriptionWorkQueue,
        speakerLabel: String
    ) {
        while let slice = TranscriptionPipelineSupport.popAudioSlice(
            from: &buffer,
            chunkSize: speedProfile.chunkSize
        ) {
            queue.pendingSlices.append(slice)
        }
        processQueue(queue, speakerLabel: speakerLabel)
    }

    private func processQueue(_ queue: TranscriptionWorkQueue, speakerLabel: String) {
        guard !queue.isDecoding else { return }
        guard !queue.pendingSlices.isEmpty else { return }

        let slice = queue.pendingSlices.removeFirst()
        let energy = TranscriptionPipelineSupport.rms(slice)
        guard TranscriptionPipelineSupport.shouldTranscribeSlice(
            energy: energy,
            minimumEnergy: speedProfile.minimumEnergy
        ) else {
            processQueue(queue, speakerLabel: speakerLabel)
            return
        }

        if TranscriptionPipelineSupport.shouldSkipEchoBleed(
            speakerLabel: speakerLabel,
            sourceMode: sourceMode,
            micEnergy: energy,
            systemReferenceEnergy: max(recentSystemEnergy, systemLevel),
            microphoneInputKind: capture.microphoneInputKind
        ) {
            statusMessage = "Filtered echo bleed from speakers."
            processQueue(queue, speakerLabel: speakerLabel)
            return
        }

        if queue.pendingSlices.count > 1 {
            statusMessage = "Transcription catching up (\(queue.pendingSlices.count) chunks queued)…"
        }

        queue.isDecoding = true

        let transcriber = self.transcriber
        Task {
            do {
                let text = try await transcriber.transcribe(audio: slice) { partialText in
                    Task { @MainActor in
                        self.updatePartialSegment(text: partialText, speakerLabel: speakerLabel)
                    }
                }
                await MainActor.run {
                    self.finishSlice(
                        text: text,
                        queue: queue,
                        speakerLabel: speakerLabel
                    )
                }
            } catch {
                await MainActor.run {
                    self.clearPartialSegment(speakerLabel: speakerLabel)
                    queue.isDecoding = false
                    self.statusMessage = "Transcription error: \(error.localizedDescription)"
                    self.processQueue(queue, speakerLabel: speakerLabel)
                }
            }
        }
    }

    private func finishSlice(
        text: String,
        queue: TranscriptionWorkQueue,
        speakerLabel: String
    ) {
        clearPartialSegment(speakerLabel: speakerLabel)
        let normalized = TranscriptionPipelineSupport.normalizeTranscriptText(text)
        let lastFinalText = lastFinalText(for: speakerLabel)
        let recentSystemTexts = speakerLabel == "You" ? recentFinalTexts(for: "System") : []
        if TranscriptionPipelineSupport.shouldAppendFinalSegment(
            text: normalized,
            speakerLabel: speakerLabel,
            lastFinalText: lastFinalText,
            recentOtherSpeakerTexts: recentSystemTexts,
            sourceMode: sourceMode
        ) {
            appendFinalSegment(normalized, speakerLabel: speakerLabel)
            statusMessage = "Transcribing \(speakerLabel)…"
        } else if !normalized.isEmpty,
                  speakerLabel == "You",
                  TranscriptionPipelineSupport.isEchoOfOtherSpeaker(normalized, otherSpeakerRecentTexts: recentSystemTexts) {
            statusMessage = "Filtered mic bleed from meeting audio."
        } else if normalized.isEmpty {
            statusMessage = "Listening… (no speech detected in last \(speakerLabel) chunk)"
        }
        queue.isDecoding = false
        processQueue(queue, speakerLabel: speakerLabel)
    }

    private func lastFinalText(for speakerLabel: String) -> String? {
        segments.last(where: { $0.isFinal && $0.speakerLabel == speakerLabel })?.text
    }

    private func recentFinalTexts(for speakerLabel: String, limit: Int = 6) -> [String] {
        segments
            .filter { $0.isFinal && $0.speakerLabel == speakerLabel }
            .suffix(limit)
            .map(\.text)
    }

    private func updatePartialSegment(text: String, speakerLabel: String) {
        let trimmed = TranscriptionPipelineSupport.normalizeTranscriptText(text)
        guard !trimmed.isEmpty, !TranscriptionPipelineSupport.looksLikeHallucination(trimmed) else {
            return
        }

        if let index = segments.lastIndex(where: { !$0.isFinal && $0.speakerLabel == speakerLabel }) {
            var segment = segments[index]
            segment.text = trimmed
            segment.language = LanguageDetector.detect(from: trimmed)
            segments[index] = segment
        } else {
            let segment = TranscriptSegment(
                id: UUID(),
                timestamp: Date(),
                text: trimmed,
                isFinal: false,
                language: LanguageDetector.detect(from: trimmed),
                speakerLabel: speakerLabel
            )
            segments.append(segment)
        }
    }

    private func clearPartialSegment(speakerLabel: String) {
        segments.removeAll { !$0.isFinal && $0.speakerLabel == speakerLabel }
    }

    private func appendFinalSegment(
        _ text: String,
        speakerLabel: String?,
        phase: TranscriptSegmentPhase = .refined,
        utteranceID: UUID? = nil,
        revisedAt: Date? = nil
    ) {
        guard var session else { return }
        let language = LanguageDetector.detect(from: text)
        let normalizedSpeaker = speakerLabel ?? "Speaker ?"
        let segment = TranscriptSegment(
            id: UUID(),
            timestamp: Date(),
            text: text,
            isFinal: true,
            language: language,
            speakerLabel: normalizedSpeaker,
            phase: phase,
            utteranceID: utteranceID,
            revisedAt: revisedAt
        )

        segments.append(segment)
        session.segments.append(segment)
        self.session = session
        Task {
            try? await store?.saveCheckpoint(session)
            if Date().timeIntervalSince(lastChunkSaveAt) > 15 {
                try? await store?.appendChunk(sessionID: session.id, text: text)
                await MainActor.run {
                    self.lastChunkSaveAt = Date()
                }
            }
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                let interval = Int(Date().timeIntervalSince(startedAt))
                self.elapsedText = Self.format(interval: interval)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func applySpeedProfile() async {
        let folder = modelFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFolder = folder.isEmpty ? nil : folder
        await transcriber.configure(localModelFolder: normalizedFolder, speedProfileRawValue: speedProfile.rawValue)
        if !isRunning {
            modelPreparationMessage = "\(speedProfile.displayName) profile: \(speedProfile.detail)"
        }
    }

    private static func format(interval: Int) -> String {
        let h = interval / 3600
        let m = (interval % 3600) / 60
        let s = interval % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

private final class SpeakerUtteranceState {
    var buffer: UtteranceBuffer
    var utteranceID = UUID()
    var pendingDrafts: [[Float]] = []
    var pendingRefines: [(audio: [Float], utteranceID: UUID)] = []
    var isDraftDecoding = false
    var isRefining = false
    var accumulatedDraftText = ""

    init(minimumEnergy: Float, draftHopSeconds: Double, maxUtteranceSeconds: Double) {
        buffer = UtteranceBuffer(
            draftHopSeconds: draftHopSeconds,
            maxUtteranceSeconds: maxUtteranceSeconds,
            minimumEnergy: minimumEnergy
        )
    }

    func reset(
        minimumEnergy: Float,
        draftHopSeconds: Double,
        maxUtteranceSeconds: Double
    ) {
        buffer = UtteranceBuffer(
            draftHopSeconds: draftHopSeconds,
            maxUtteranceSeconds: maxUtteranceSeconds,
            minimumEnergy: minimumEnergy
        )
        utteranceID = UUID()
        pendingDrafts = []
        pendingRefines = []
        isDraftDecoding = false
        isRefining = false
        accumulatedDraftText = ""
    }
}

private final class TranscriptionWorkQueue {
    var pendingSlices: [[Float]] = []
    var isDecoding = false

    func reset() {
        pendingSlices = []
        isDecoding = false
    }
}
