import CSherpaOnnx
import Foundation

actor SenseVoiceTranscriber {
    private var recognizer: OpaquePointer?
    private var localModelFolder: String?
    private var isInitialized = false

    func configure(localModelFolder: String?) {
        let normalized = localModelFolder?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newFolder: String?
        if let normalized, !normalized.isEmpty {
            newFolder = normalized
        } else {
            newFolder = nil
        }

        if self.localModelFolder != newFolder {
            self.localModelFolder = newFolder
            destroyRecognizer()
            isInitialized = false
        }
    }

    func prepareIfNeeded(statusHandler: ((ModelPreparationStatus) -> Void)? = nil) async throws {
        if isInitialized, recognizer != nil { return }

        let modelDir = resolveModelDirectory()
        guard let modelDir else {
            throw SenseVoiceTranscriberError.modelNotFound
        }

        statusHandler?(ModelPreparationStatus(message: "Loading SenseVoice-Small (\(modelDir))...", progress: nil))

        guard let rec = Self.makeRecognizer(modelDir: modelDir) else {
            throw SenseVoiceTranscriberError.initializationFailed
        }

        recognizer = rec
        isInitialized = true
        statusHandler?(ModelPreparationStatus(message: "SenseVoice-Small ready", progress: 1.0))
    }

    func transcribe(
        audio: [Float],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await prepareIfNeeded()
        guard let recognizer else { return "" }
        guard !audio.isEmpty else { return "" }

        let text = Self.decode(audio: audio, recognizer: recognizer)
        let cleaned = SenseVoiceTextCleaner.clean(text)
        if !cleaned.isEmpty {
            onProgress?(cleaned)
        }
        return cleaned
    }

    private func destroyRecognizer() {
        if let recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
            self.recognizer = nil
        }
    }

    private func resolveModelDirectory() -> String? {
        if let localModelFolder,
           let resolved = Self.findModelDirectory(in: localModelFolder) {
            return resolved
        }
        return Self.defaultModelDirectory()
    }

    private static func defaultModelDirectory() -> String? {
        var candidates = [ModelStoragePaths.defaultSenseVoiceDirectory, ModelStoragePaths.defaultModelsDirectory]

        if let modelsDir = ProcessInfo.processInfo.environment["LIVESCRIPT_MODELS_DIR"],
           !modelsDir.isEmpty {
            candidates.insert((modelsDir as NSString).appendingPathComponent("sensevoice"), at: 0)
            candidates.insert(modelsDir, at: 1)
        }
        if let senseVoiceDir = ProcessInfo.processInfo.environment["LIVESCRIPT_SENSEVOICE_MODEL_DIR"],
           !senseVoiceDir.isEmpty {
            candidates.insert(senseVoiceDir, at: 0)
        }

        for candidate in candidates {
            if let resolved = findModelDirectory(in: candidate) {
                return resolved
            }
        }
        return nil
    }

    private static func findModelDirectory(in basePath: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: basePath, isDirectory: &isDir), isDir.boolValue else { return nil }

        if hasModelFiles(at: basePath) {
            return basePath
        }

        let nestedCandidates = [
            "\(basePath)/sensevoice",
            "\(basePath)/SenseVoice",
            "\(basePath)/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
        ]
        for nested in nestedCandidates where hasModelFiles(at: nested) {
            return nested
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { return nil }
        for entry in entries where entry.localizedCaseInsensitiveContains("sense-voice") {
            let full = "\(basePath)/\(entry)"
            if hasModelFiles(at: full) {
                return full
            }
        }
        return nil
    }

    private static func hasModelFiles(at path: String) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: "\(path)/model.int8.onnx")
            && fm.fileExists(atPath: "\(path)/tokens.txt")
    }

    private static func makeRecognizer(modelDir: String) -> OpaquePointer? {
        let modelPath = (modelDir as NSString).appendingPathComponent("model.int8.onnx")
        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")

        var config = SherpaOnnxOfflineRecognizerConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineRecognizerConfig>.size)

        config.feat_config.sample_rate = 16_000
        config.feat_config.feature_dim = 80
        config.model_config.sense_voice.model = persistentCString(modelPath)
        config.model_config.sense_voice.language = persistentCString("auto")
        config.model_config.sense_voice.use_itn = 1
        config.model_config.tokens = persistentCString(tokensPath)
        config.model_config.num_threads = 2
        config.model_config.provider = persistentCString("cpu")
        config.model_config.debug = 0
        config.decoding_method = persistentCString("greedy_search")

        return SherpaOnnxCreateOfflineRecognizer(&config)
    }

    private static func persistentCString(_ value: String) -> UnsafePointer<CChar>? {
        guard let mutable = strdup(value) else { return nil }
        return UnsafePointer(mutable)
    }

    private static func decode(audio: [Float], recognizer: OpaquePointer) -> String {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }

        audio.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            SherpaOnnxAcceptWaveformOffline(stream, 16_000, base, Int32(buffer.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }

        if let textPointer = result.pointee.text {
            return String(cString: textPointer)
        }
        return ""
    }
}

enum SenseVoiceTranscriberError: LocalizedError {
    case modelNotFound
    case initializationFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "SenseVoice-Small model not found in ~/workspace/models/sensevoice. Run scripts/download_sensevoice_model.sh or choose a model folder containing model.int8.onnx and tokens.txt."
        case .initializationFailed:
            return "Failed to initialize SenseVoice-Small recognizer."
        }
    }
}
