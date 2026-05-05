import Foundation
import SpeakerKit

actor SpeakerDiarizer {
    private var speakerKit: SpeakerKit?
    private var downloadBaseFolder: String?

    func configure(downloadBaseFolder: String?) {
        let normalized = downloadBaseFolder?.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.downloadBaseFolder != normalized {
            self.downloadBaseFolder = normalized
            speakerKit = nil
        }
    }

    func prepareIfNeeded() async throws {
        if speakerKit != nil { return }
        let config: SpeakerKitConfig
        if let base = downloadBaseFolder, !base.isEmpty,
           let localModelFolder = resolveLocalSpeakerFolder(from: base) {
            config = PyannoteConfig(modelFolder: localModelFolder, download: false, load: true, verbose: false)
        } else if let base = downloadBaseFolder, !base.isEmpty {
            config = PyannoteConfig(downloadBase: base, download: true, load: true, verbose: false)
        } else {
            config = PyannoteConfig(download: true, load: true, verbose: false)
        }
        speakerKit = try await SpeakerKit(config)
    }

    func dominantSpeakerLabel(audio: [Float]) async -> String? {
        do {
            try await prepareIfNeeded()
            guard let speakerKit else { return nil }
            let result = try await speakerKit.diarize(audioArray: audio)
            guard !result.segments.isEmpty else { return nil }

            var durations: [Int: Float] = [:]
            for segment in result.segments {
                guard let speakerID = segment.speaker.speakerId else { continue }
                durations[speakerID, default: 0] += max(0, segment.endTime - segment.startTime)
            }

            guard let top = durations.max(by: { $0.value < $1.value })?.key else { return nil }
            return "Speaker \(top)"
        } catch {
            return nil
        }
    }

    private func resolveLocalSpeakerFolder(from selectedPath: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        let direct = selectedPath
        if containsSpeakerModelFiles(at: direct) {
            return direct
        }

        let repoCandidates = [
            "\(selectedPath)/argmaxinc/speakerkit-coreml",
            "\(selectedPath)/models/argmaxinc/speakerkit-coreml",
            "\(selectedPath)/huggingface_models/argmaxinc/speakerkit-coreml"
        ]

        for repo in repoCandidates where fm.fileExists(atPath: repo, isDirectory: &isDir) && isDir.boolValue {
            if containsSpeakerModelFiles(at: repo) {
                return repo
            }
        }
        return nil
    }

    private func containsSpeakerModelFiles(at path: String) -> Bool {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return false }
        let expected = ["speaker_segmenter", "speaker_embedder", "speaker_clusterer"]
        return expected.allSatisfy { items.contains($0) }
    }
}
