import Foundation
import WhisperKit

struct ModelPreparationStatus: Sendable {
    let message: String
    let progress: Double?
}

actor WhisperTranscriber {
    private var whisperKit: WhisperKit?
    private var localModelFolder: String?
    private var fallbackModelName: String
    private var didInitialize = false
    private var decodeOptions = DecodingOptions(
        temperature: 0.0,
        usePrefillPrompt: true,
        detectLanguage: true,
        logProbThreshold: -0.5,
        firstTokenLogProbThreshold: -1.0,
        noSpeechThreshold: 0.8
    )

    init(fallbackModelName: String = "large-v3-v20240930_626MB") {
        self.fallbackModelName = fallbackModelName
    }

    func configure(localModelFolder: String?, fallbackModelName: String) {
        let normalizedFolder: String?
        if let localModelFolder, !localModelFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalizedFolder = localModelFolder
        } else {
            normalizedFolder = nil
        }

        let needsReset = self.localModelFolder != normalizedFolder || self.fallbackModelName != fallbackModelName
        self.localModelFolder = normalizedFolder
        self.fallbackModelName = fallbackModelName
        if needsReset {
            whisperKit = nil
            didInitialize = false
        }
    }

    func prepareIfNeeded(statusHandler: ((ModelPreparationStatus) -> Void)? = nil) async throws {
        if didInitialize, whisperKit != nil { return }

        if let localModelFolder {
            do {
                statusHandler?(ModelPreparationStatus(message: "Loading local model...", progress: nil))
                let localConfig = WhisperKitConfig(
                    modelFolder: localModelFolder,
                    verbose: false,
                    load: true,
                    download: false
                )
                whisperKit = try await WhisperKit(localConfig)
                didInitialize = true
                statusHandler?(ModelPreparationStatus(message: "Model ready (local)", progress: 1.0))
                return
            } catch {
                statusHandler?(ModelPreparationStatus(message: "Local model failed, downloading fallback...", progress: 0.0))
            }
        }

        statusHandler?(ModelPreparationStatus(message: "Downloading fallback model...", progress: 0.0))
        let downloadBase = localModelFolder.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let downloadedModelFolder = try await WhisperKit.download(
            variant: fallbackModelName,
            downloadBase: downloadBase,
            progressCallback: { progress in
                statusHandler?(ModelPreparationStatus(message: "Downloading fallback model...", progress: progress.fractionCompleted))
            }
        )

        let downloadedConfig = WhisperKitConfig(
            modelFolder: downloadedModelFolder.path,
            verbose: false,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(downloadedConfig)
        didInitialize = true
        statusHandler?(ModelPreparationStatus(message: "Model ready (downloaded)", progress: 1.0))
    }

    func transcribe(audio: [Float]) async throws -> String {
        try await prepareIfNeeded()
        guard let whisperKit else { return "" }
        let result = try await whisperKit.transcribe(audioArray: audio, decodeOptions: decodeOptions)
        if let first = result.first {
            return first.text
        }
        return ""
    }
}
