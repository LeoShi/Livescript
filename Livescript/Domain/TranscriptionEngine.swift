import Foundation

enum TranscriptionEngine: String, Codable, CaseIterable, Identifiable {
    case senseVoice
    case whisper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .senseVoice: return "SenseVoice"
        case .whisper: return "Whisper"
        }
    }
}
