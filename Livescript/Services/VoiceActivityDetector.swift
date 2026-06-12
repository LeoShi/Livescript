import CSherpaOnnx
import Foundation

/// Optional Silero VAD for smarter utterance boundaries in Smart captions.
actor VoiceActivityDetector {
    private var vad: OpaquePointer?
    private var isReady = false

    func configure(localModelFolder: String?) {
        // Re-resolve on next prepare; model path depends on folder layout.
        _ = localModelFolder
    }

    func prepareIfNeeded() async {
        if isReady, vad != nil { return }
        guard let modelPath = resolveModelPath() else { return }
        guard Self.isValidOnnxFile(at: modelPath) else { return }

        var config = SherpaOnnxVadModelConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxVadModelConfig>.size)
        config.silero_vad.model = Self.persistentCString(modelPath)
        config.silero_vad.threshold = 0.45
        config.silero_vad.min_silence_duration = 0.25
        config.silero_vad.min_speech_duration = 0.12
        config.silero_vad.window_size = 512
        config.silero_vad.max_speech_duration = 30
        config.sample_rate = 16_000
        config.num_threads = 1
        config.provider = Self.persistentCString("cpu")

        guard let instance = SherpaOnnxCreateVoiceActivityDetector(&config, 60) else { return }
        vad = instance
        isReady = true
    }

    var isAvailable: Bool {
        vad != nil
    }

    func isSpeech(in chunk: [Float]) -> Bool {
        guard let vad, !chunk.isEmpty else { return false }
        chunk.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, base, Int32(buffer.count))
        }
        return SherpaOnnxVoiceActivityDetectorDetected(vad) != 0
    }

    func reset() {
        if let vad {
            SherpaOnnxVoiceActivityDetectorReset(vad)
        }
    }

    private func resolveModelPath() -> String? {
        var candidates = [
            ModelStoragePaths.defaultVADDirectory + "/silero_vad.onnx",
            ModelStoragePaths.defaultModelsDirectory + "/vad/silero_vad.onnx"
        ]
        if let env = ProcessInfo.processInfo.environment["LIVESCRIPT_VAD_MODEL_DIR"],
           !env.isEmpty {
            candidates.insert(env + "/silero_vad.onnx", at: 0)
        }
        return candidates.first { Self.isValidOnnxFile(at: $0) }
    }

    private static let minimumModelBytes: Int64 = 100_000

    private static func isValidOnnxFile(at path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64,
              size >= minimumModelBytes else {
            return false
        }
        return true
    }

    private static func persistentCString(_ value: String) -> UnsafePointer<CChar>? {
        guard let mutable = strdup(value) else { return nil }
        return UnsafePointer(mutable)
    }
}
