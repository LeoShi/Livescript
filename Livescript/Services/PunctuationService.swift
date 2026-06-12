import CSherpaOnnx
import Foundation

actor PunctuationService {
    private var punctuator: OpaquePointer?
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
            destroyPunctuator()
            isInitialized = false
        }
    }

    func prepareIfNeeded() async throws {
        if isInitialized, punctuator != nil { return }
        guard let modelPath = resolveModelPath() else { return }
        guard Self.isValidOnnxFile(at: modelPath) else { return }

        var config = SherpaOnnxOfflinePunctuationConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflinePunctuationConfig>.size)
        config.model.ct_transformer = Self.persistentCString(modelPath)
        config.model.num_threads = 1
        config.model.debug = 0
        config.model.provider = Self.persistentCString("cpu")

        guard let instance = SherpaOnnxCreateOfflinePunctuation(&config) else { return }
        punctuator = instance
        isInitialized = true
    }

    func addPunctuation(to text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        do {
            try await prepareIfNeeded()
        } catch {
            return text
        }

        guard let punctuator else { return text }

        guard let resultPointer = trimmed.withCString({ input in
            SherpaOfflinePunctuationAddPunct(punctuator, input)
        }) else {
            return text
        }
        defer { SherpaOfflinePunctuationFreeText(resultPointer) }
        return String(cString: resultPointer)
    }

    private func destroyPunctuator() {
        if let punctuator {
            SherpaOnnxDestroyOfflinePunctuation(punctuator)
            self.punctuator = nil
        }
    }

    private func resolveModelPath() -> String? {
        let candidates = buildModelCandidates()
        for candidate in candidates where Self.isValidOnnxFile(at: candidate) {
            return candidate
        }
        return nil
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

    private func buildModelCandidates() -> [String] {
        var roots = [ModelStoragePaths.defaultPunctuationDirectory]
        if let localModelFolder {
            roots.insert(localModelFolder, at: 0)
            roots.insert("\(localModelFolder)/punctuation", at: 1)
        }
        if let env = ProcessInfo.processInfo.environment["LIVESCRIPT_PUNCTUATION_MODEL_DIR"], !env.isEmpty {
            roots.insert(env, at: 0)
        }

        let filenames = [
            "model.onnx",
            "model.int8.onnx",
            "punct-ct-transformer-zh-en-vocab272727-onnx/model.onnx"
        ]

        var paths: [String] = []
        for root in roots {
            for name in filenames {
                paths.append((root as NSString).appendingPathComponent(name))
            }
        }
        return paths
    }

    private static func persistentCString(_ value: String) -> UnsafePointer<CChar>? {
        guard let mutable = strdup(value) else { return nil }
        return UnsafePointer(mutable)
    }
}
