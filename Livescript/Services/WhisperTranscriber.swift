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
    private var usesStrictDecode = false
    private var usesLongForm = false
    private var didInitialize = false
    private var decodeOptions = makeDecodeOptions(strict: false, language: nil, longForm: false)

    init(fallbackModelName: String = "small") {
        self.fallbackModelName = fallbackModelName
    }

    func configure(
        localModelFolder: String?,
        fallbackModelName: String,
        usesStrictDecodeThresholds: Bool = false
    ) {
        let normalizedFolder: String?
        if let localModelFolder, !localModelFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalizedFolder = localModelFolder
        } else {
            normalizedFolder = nil
        }

        let longForm = fallbackModelName.localizedCaseInsensitiveContains("distil")
            || fallbackModelName.localizedCaseInsensitiveContains("large")
        let newDecodeOptions = Self.makeDecodeOptions(
            strict: usesStrictDecodeThresholds,
            language: nil,
            longForm: longForm
        )
        let needsReset = self.localModelFolder != normalizedFolder
            || self.fallbackModelName != fallbackModelName
            || self.usesStrictDecode != usesStrictDecodeThresholds
            || self.usesLongForm != longForm
            || self.decodeOptions.sampleLength != newDecodeOptions.sampleLength
            || self.decodeOptions.logProbThreshold != newDecodeOptions.logProbThreshold
        self.localModelFolder = normalizedFolder
        self.fallbackModelName = fallbackModelName
        self.usesStrictDecode = usesStrictDecodeThresholds
        self.usesLongForm = longForm
        self.decodeOptions = newDecodeOptions
        if needsReset {
            whisperKit = nil
            didInitialize = false
        }
    }

    private static func makeDecodeOptions(strict: Bool, language: String?, longForm: Bool) -> DecodingOptions {
        let sampleLength = longForm ? 224 : (strict ? 224 : 128)
        let detectLanguage = language == nil
        if strict {
            return DecodingOptions(
                language: language,
                temperature: 0.0,
                sampleLength: sampleLength,
                usePrefillPrompt: true,
                detectLanguage: detectLanguage,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                wordTimestamps: false,
                suppressBlank: true,
                logProbThreshold: -0.5,
                firstTokenLogProbThreshold: -1.0,
                noSpeechThreshold: 0.6
            )
        }

        return DecodingOptions(
            language: language,
            temperature: 0.0,
            sampleLength: sampleLength,
            usePrefillPrompt: true,
            detectLanguage: detectLanguage,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            suppressBlank: true,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6
        )
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
            statusHandler?(ModelPreparationStatus(message: "No matching local model, downloading \(fallbackModelName)...", progress: 0.0))
        }

        let variant = fallbackModelName
        statusHandler?(ModelPreparationStatus(message: "Downloading \(variant) model...", progress: 0.0))
        let downloadBase = localModelFolder.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let downloadedModelFolder = try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            progressCallback: { progress in
                statusHandler?(ModelPreparationStatus(message: "Downloading \(variant) model...", progress: progress.fractionCompleted))
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

    func transcribe(
        audio: [Float],
        language: String? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await prepareIfNeeded()
        guard let whisperKit else { return "" }

        let options = Self.makeDecodeOptions(
            strict: usesStrictDecode,
            language: language,
            longForm: usesLongForm
        )

        let results = try await whisperKit.transcribe(
            audioArray: audio,
            decodeOptions: options,
            callback: { progress in
                let text = progress.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    onProgress?(text)
                }
                return nil
            }
        )

        if let first = results.first {
            return first.text
        }
        return ""
    }

    private func resolveLocalWhisperFolder(from selectedPath: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: selectedPath, isDirectory: &isDir), isDir.boolValue else { return nil }

        let variantCandidates = variantFolderNames(for: fallbackModelName)

        let repoCandidates = [
            "\(selectedPath)/argmaxinc/whisperkit-coreml",
            "\(selectedPath)/models/argmaxinc/whisperkit-coreml",
            "\(selectedPath)/huggingface_models/argmaxinc/whisperkit-coreml"
        ]

        for repo in repoCandidates where fm.fileExists(atPath: repo, isDirectory: &isDir) && isDir.boolValue {
            for variant in variantCandidates {
                let modelPath = "\(repo)/\(variant)"
                if containsWhisperModelFiles(at: modelPath) {
                    return modelPath
                }
            }
        }

        if let nestedMatch = findVariantFolder(in: selectedPath, variantCandidates: variantCandidates) {
            return nestedMatch
        }

        if containsWhisperModelFiles(at: selectedPath),
           pathMatchesVariant(selectedPath, variantCandidates: variantCandidates) {
            return selectedPath
        }

        return nil
    }

    private func variantFolderNames(for variant: String) -> [String] {
        if variant.localizedCaseInsensitiveContains("distil") {
            return [
                "distil-whisper_distil-\(variant)",
                "distil-whisper_\(variant)",
                "openai_whisper-\(variant)",
                variant
            ]
        }
        return [
            "openai_whisper-\(variant)",
            variant
        ]
    }

    private func findVariantFolder(in root: String, variantCandidates: [String]) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { return nil }
        for entry in entries {
            let fullPath = "\(root)/\(entry)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard variantCandidates.contains(where: { entry.localizedCaseInsensitiveContains($0) }) else { continue }
            if containsWhisperModelFiles(at: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    private func pathMatchesVariant(_ path: String, variantCandidates: [String]) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return variantCandidates.contains { candidate in
            name.contains(candidate.lowercased())
        }
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
