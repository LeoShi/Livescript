import Foundation

enum ModelStoragePaths {
    nonisolated static var defaultModelsDirectory: String {
        expandTilde("~/workspace/models")
    }

    nonisolated static var defaultSenseVoiceDirectory: String {
        (defaultModelsDirectory as NSString).appendingPathComponent("sensevoice")
    }

    nonisolated static var defaultVADDirectory: String {
        (defaultModelsDirectory as NSString).appendingPathComponent("vad")
    }

    nonisolated static var defaultPunctuationDirectory: String {
        (defaultModelsDirectory as NSString).appendingPathComponent("punctuation")
    }

    nonisolated static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        return NSHomeDirectory() + String(path.dropFirst(1))
    }
}
