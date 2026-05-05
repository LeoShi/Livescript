import Foundation

enum TranscriptLanguage: String, Codable {
    case english = "en"
    case chinese = "zh"
    case mixed = "mixed"
    case unknown = "unknown"
}

enum TranscriptSourceMode: String, Codable, CaseIterable {
    case mic
    case system
    case mixed
}

struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var text: String
    var isFinal: Bool
    var language: TranscriptLanguage
}

struct TranscriptSession: Codable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let sourceMode: TranscriptSourceMode
    var segments: [TranscriptSegment]
}
