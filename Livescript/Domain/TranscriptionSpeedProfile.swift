import Foundation

/// Controls the latency vs accuracy trade-off for live transcription.
enum TranscriptionSpeedProfile: String, CaseIterable, Codable, Identifiable {
    case smart
    case balanced
    case quality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smart: return "Smart"
        case .balanced: return "Balanced"
        case .quality: return "Quality"
        }
    }

    var detail: String {
        switch self {
        case .smart:
            return "SenseVoice draft; English refine (distil-large-v3), Chinese refine (SenseVoice)."
        case .balanced:
            return "Whisper small, 2s chunks. Good mix."
        case .quality:
            return "Whisper large v3, 2s chunks. Best accuracy."
        }
    }

    var usesSmartCaptions: Bool {
        self == .smart
    }

    var engine: TranscriptionEngine {
        switch self {
        case .smart:
            return .senseVoice
        case .balanced, .quality:
            return .whisper
        }
    }

    var modelLabel: String {
        switch self {
        case .smart:
            return "SenseVoice + distil-large-v3"
        case .balanced:
            return "Whisper small"
        case .quality:
            return "Whisper large-v3"
        }
    }

    var chunkSize: Int {
        switch self {
        case .smart:
            return 24_000
        case .balanced, .quality:
            return 32_000
        }
    }

    var minimumEnergy: Float {
        switch self {
        case .smart:
            return 0.0035
        case .balanced:
            return 0.0025
        case .quality:
            return 0.004
        }
    }

    var draftHopSeconds: Double {
        switch self {
        case .smart:
            return 1.0
        case .balanced, .quality:
            return 1.5
        }
    }

    var maxUtteranceSeconds: Double {
        switch self {
        case .smart:
            return 8
        case .balanced, .quality:
            return 10
        }
    }

    var usesStrictDecodeThresholds: Bool {
        self == .quality
    }

    nonisolated static let refineWhisperModelVariant = "distil-large-v3"

    nonisolated static func engine(for rawValue: String) -> TranscriptionEngine {
        if rawValue == TranscriptionSpeedProfile.smart.rawValue {
            return .senseVoice
        }
        return .whisper
    }

    nonisolated static func usesSmartCaptions(for rawValue: String) -> Bool {
        rawValue == TranscriptionSpeedProfile.smart.rawValue
            || rawValue == "realtime"
    }

    nonisolated static func whisperModelVariant(for rawValue: String) -> String {
        switch rawValue {
        case TranscriptionSpeedProfile.quality.rawValue:
            return "large-v3-v20240930_626MB"
        default:
            return "small"
        }
    }

    nonisolated static func usesStrictDecode(for rawValue: String) -> Bool {
        rawValue == TranscriptionSpeedProfile.quality.rawValue
    }

    var expectedLatencySeconds: String {
        switch self {
        case .smart:
            return "draft ~0.5–1.5s, refine ~2–3.5s"
        case .balanced:
            return "~2–3s"
        case .quality:
            return "~4–6s"
        }
    }
}
