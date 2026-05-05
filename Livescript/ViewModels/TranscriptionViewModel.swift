import AppKit
import Combine
import Foundation

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var sourceMode: TranscriptSourceMode = .mixed
    @Published var isRunning = false
    @Published var captureHiddenStatus = "Hidden from capture: best effort"
    @Published var statusMessage = "Idle"
    @Published var segments: [TranscriptSegment] = []
    @Published var elapsedText = "00:00:00"
    @Published var modelFolderPath: String = UserDefaults.standard.string(forKey: "ModelFolderPath") ?? ""
    @Published var modelPreparationMessage = "Model not prepared"
    @Published var modelDownloadProgress: Double?

    private var session: TranscriptSession?
    private var audioBuffer: [Float] = []
    private var startedAt: Date?
    private var timer: Timer?
    private var lastChunkSaveAt: Date = .distantPast

    private let capture = AudioCaptureCoordinator()
    private let transcriber = WhisperTranscriber(fallbackModelName: "large-v3-v20240930_626MB")
    private var store: SessionStore?

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
        audioBuffer = []
        lastChunkSaveAt = .distantPast

        capture.onPCMChunk = { [weak self] chunk in
            Task { @MainActor in
                await self?.consumeAudio(chunk)
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

    private func consumeAudio(_ chunk: [Float]) async {
        guard isRunning else { return }
        audioBuffer.append(contentsOf: chunk)

        // Process roughly every 5 seconds at 16kHz.
        let chunkSize = 80_000
        guard audioBuffer.count >= chunkSize else { return }
        let audioSlice = Array(audioBuffer.prefix(chunkSize))
        audioBuffer.removeFirst(min(chunkSize / 2, audioBuffer.count))

        do {
            let text = try await transcriber.transcribe(audio: audioSlice)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            appendFinalSegment(trimmed)
            statusMessage = "Transcribing..."
        } catch {
            statusMessage = "Transcription error: \(error.localizedDescription)"
        }
    }

    private func appendFinalSegment(_ text: String) {
        guard var session else { return }
        let language = LanguageDetector.detect(from: text)
        let segment = TranscriptSegment(
            id: UUID(),
            timestamp: Date(),
            text: text,
            isFinal: true,
            language: language
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
}
