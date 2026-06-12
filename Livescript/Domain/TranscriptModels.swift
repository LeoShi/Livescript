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
    var speakerLabel: String?
    var phase: TranscriptSegmentPhase
    var utteranceID: UUID?
    var revisedAt: Date?

    init(
        id: UUID,
        timestamp: Date,
        text: String,
        isFinal: Bool,
        language: TranscriptLanguage,
        speakerLabel: String?,
        phase: TranscriptSegmentPhase? = nil,
        utteranceID: UUID? = nil,
        revisedAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.isFinal = isFinal
        self.language = language
        self.speakerLabel = speakerLabel
        if let phase {
            self.phase = phase
        } else {
            self.phase = isFinal ? .refined : .draft
        }
        self.utteranceID = utteranceID
        self.revisedAt = revisedAt
    }
}

struct TranscriptSession: Codable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let sourceMode: TranscriptSourceMode
    var segments: [TranscriptSegment]
}
