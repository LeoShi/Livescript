import AppKit
import Combine
import Foundation

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var sourceMode: TranscriptSourceMode = .mixed
    @Published var isRunning = false
    @Published var captureHiddenStatus = "Hidden from capture: best effort"
    @Published var statusMessage = "Idle"
    @Published var systemCaptureStatus = "System audio: idle"
    @Published var segments: [TranscriptSegment] = []
    @Published var elapsedText = "00:00:00"
    @Published var modelFolderPath: String = UserDefaults.standard.string(forKey: "ModelFolderPath") ?? ""
    @Published var modelPreparationMessage = "Model not prepared"
    @Published var modelDownloadProgress: Double?
    @Published var transcriptIsSelectable = true
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0

    private var session: TranscriptSession?
    private var micBuffer: [Float] = []
    private var systemBuffer: [Float] = []
    private var startedAt: Date?
    private var timer: Timer?
    private var lastChunkSaveAt: Date = .distantPast
    private var lastSystemChunkAt: Date = .distantPast
    /// Exponential moving average of recent system audio energy. Used as an echo-bleed
    /// reference so we don't transcribe YouTube playing through speakers as the user.
    private var recentSystemEnergy: Float = 0

    private let capture = AudioCaptureCoordinator()
    private let transcriber = WhisperTranscriber(fallbackModelName: "large-v3-v20240930_626MB")
    private let speakerDiarizer = SpeakerDiarizer()
    private var store: SessionStore?

    /// 3 seconds at 16 kHz. Smaller windows trade a small amount of accuracy
    /// (less context per pass) for noticeably lower visible latency.
    private static let transcriptionChunkSize = 48_000

    func start() async {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Folder for Session Data"
        panel.canCreateDirectories = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let base = panel.url else {
            statusMessage = "Canceled folder selection."
            return
        }

        let dir = base.appendingPathComponent("MeetingSession_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        store = SessionStore(baseDirectory: dir)
        await transcriber.configure(
            localModelFolder: modelFolderPath.trimmingCharacters(in: .whitespacesAndNewlines),
            fallbackModelName: "large-v3-v20240930_626MB"
        )
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
            statusMessage = "Model setup failed: \(error.localizedDescription)"
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
            statusMessage = "Live transcription running."
        } catch {
            statusMessage = "Capture start failed: \(error.localizedDescription)"
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
        statusMessage = "Model folder set. Local-first loading enabled."
        modelPreparationMessage = "Model folder updated"
        modelDownloadProgress = nil
    }

    func clearModelFolder() {
        modelFolderPath = ""
        UserDefaults.standard.removeObject(forKey: "ModelFolderPath")
        statusMessage = "Model folder cleared. Network fallback only."
        modelPreparationMessage = "Model folder cleared"
        modelDownloadProgress = nil
    }

    func stop() {
        guard isRunning else { return }
        capture.stop()
        stopTimer()
        isRunning = false
        statusMessage = "Stopped."
        systemCaptureStatus = "System audio: idle"
        micLevel = 0
        systemLevel = 0

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
            statusMessage = "Export failed: \(error.localizedDescription)"
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
            let energy = Self.rms(chunk.samples)
            micLevel = energy
            guard sourceMode == .mic || sourceMode == .mixed else { return }
            micBuffer.append(contentsOf: chunk.samples)
            if let slice = popAudioSlice(from: &micBuffer, chunkSize: Self.transcriptionChunkSize) {
                scheduleTranscription(slice: slice, speakerLabel: "You")
            }
        case .system:
            let energy = Self.rms(chunk.samples)
            systemLevel = energy
            // EMA so the mic-bleed gate has a stable reference even between SCK callbacks.
            recentSystemEnergy = max(energy, recentSystemEnergy * 0.85)
            lastSystemChunkAt = Date()
            guard sourceMode == .system || sourceMode == .mixed else { return }
            systemBuffer.append(contentsOf: chunk.samples)
            if let slice = popAudioSlice(from: &systemBuffer, chunkSize: Self.transcriptionChunkSize) {
                scheduleTranscription(slice: slice, speakerLabel: "System")
            }
        }
    }

    /// Pops a fixed-size, non-overlapping window from the front of the buffer.
    private func popAudioSlice(from buffer: inout [Float], chunkSize: Int) -> [Float]? {
        guard buffer.count >= chunkSize else { return nil }
        let audioSlice = Array(buffer.prefix(chunkSize))
        buffer.removeFirst(chunkSize)
        return audioSlice
    }

    /// Fire-and-forget transcription. Runs Whisper off the main actor so capture callbacks
    /// keep flowing and the UI stays responsive while the model decodes.
    private func scheduleTranscription(slice: [Float], speakerLabel: String) {
        let energy = Self.rms(slice)
        if energy < 0.0035 { return }

        // Echo / mic-bleed gate: in mixed mode, when the system is actively playing
        // and the mic is quieter than the system, the mic is almost certainly picking up
        // speaker bleed rather than a person talking. Drop those slices.
        if speakerLabel == "You", sourceMode == .mixed {
            let systemRef = max(recentSystemEnergy, systemLevel)
            if systemRef > 0.004, energy < systemRef * 1.6 {
                statusMessage = "Filtered echo bleed from speakers."
                return
            }
        }

        let transcriber = self.transcriber
        Task {
            do {
                let text = try await transcriber.transcribe(audio: slice)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if Self.looksLikeHallucination(trimmed) { return }
                await MainActor.run {
                    self.appendFinalSegment(trimmed, speakerLabel: speakerLabel)
                    self.statusMessage = "Transcribing \(speakerLabel)…"
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Transcription error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func appendFinalSegment(_ text: String, speakerLabel: String?) {
        guard var session else { return }
        let language = LanguageDetector.detect(from: text)
        let normalizedSpeaker = speakerLabel ?? "Speaker ?"
        let segment = TranscriptSegment(
            id: UUID(),
            timestamp: Date(),
            text: text,
            isFinal: true,
            language: language,
            speakerLabel: normalizedSpeaker
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

    private static func format(interval: Int) -> String {
        let h = interval / 3600
        let m = (interval % 3600) / 60
        let s = interval % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for v in samples { sum += v * v }
        return sqrt(sum / Float(samples.count))
    }

    private static func looksLikeHallucination(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let blocked = [
            "thank you.",
            "thank you",
            "thanks for watching",
            "字幕由 amara.org 社群提供",
            "字幕由amra.org社群提供"
        ]
        return blocked.contains(normalized)
    }
}
