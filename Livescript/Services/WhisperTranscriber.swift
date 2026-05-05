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
        skipSpecialTokens: true,
        withoutTimestamps: true,
        wordTimestamps: false,
        suppressBlank: true,
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

        if let localModelFolder, let resolvedLocalFolder = resolveLocalWhisperFolder(from: localModelFolder) {
            do {
                statusHandler?(ModelPreparationStatus(message: "Loading local model (\(resolvedLocalFolder))...", progress: nil))
                let localConfig = WhisperKitConfig(
                    modelFolder: resolvedLocalFolder,
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
        } else if localModelFolder != nil {
            statusHandler?(ModelPreparationStatus(message: "No local Whisper model found, downloading fallback...", progress: 0.0))
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

    private func resolveLocalWhisperFolder(from selectedPath: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: selectedPath, isDirectory: &isDir), isDir.boolValue else { return nil }

        // 1) Direct model folder selection
        if containsWhisperModelFiles(at: selectedPath) {
            return selectedPath
        }

        // 2) Repository roots under selected base
        let repoCandidates = [
            "\(selectedPath)/argmaxinc/whisperkit-coreml",
            "\(selectedPath)/models/argmaxinc/whisperkit-coreml",
            "\(selectedPath)/huggingface_models/argmaxinc/whisperkit-coreml"
        ]

        let variantCandidates = [
            "openai_whisper-\(fallbackModelName)",
            fallbackModelName
        ]

        for repo in repoCandidates where fm.fileExists(atPath: repo, isDirectory: &isDir) && isDir.boolValue {
            for variant in variantCandidates {
                let modelPath = "\(repo)/\(variant)"
                if containsWhisperModelFiles(at: modelPath) {
                    return modelPath
                }
            }
        }

        return nil
    }

    private func containsWhisperModelFiles(at path: String) -> Bool {
        let fm = FileManager.default
        let requiredPrefixes = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return false }
        return requiredPrefixes.allSatisfy { prefix in
            items.contains(where: { $0.hasPrefix(prefix) })
        }
    }
}
