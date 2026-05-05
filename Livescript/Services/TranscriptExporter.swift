import Foundation
import UniformTypeIdentifiers

enum TranscriptExportFormat: String, CaseIterable {
    case txt
    case md
}

enum TranscriptExporter {
    static func suggestedTypes(for format: TranscriptExportFormat) -> [UTType] {
        switch format {
        case .txt:
            return [.plainText]
        case .md:
            return [.plainText]
        }
    }

    static func render(session: TranscriptSession, format: TranscriptExportFormat) -> String {
        switch format {
        case .txt:
            return session.segments
                .filter { $0.isFinal }
                .map { segment in
                    if let speaker = segment.speakerLabel, !speaker.isEmpty {
                        return "\(speaker): \(segment.text)"
                    }
                    return segment.text
                }
                .joined(separator: "\n")
        case .md:
            let header = "# Transcript\n\n- Session ID: \(session.id.uuidString)\n- Started: \(session.startedAt)\n\n"
            let body = session.segments
                .filter { $0.isFinal }
                .map { segment in
                    let speakerPrefix = (segment.speakerLabel?.isEmpty == false) ? "\(segment.speakerLabel!): " : ""
                    return "[\(timeString(segment.timestamp))] (\(segment.language.rawValue)) \(speakerPrefix)\(segment.text)"
                }
                .joined(separator: "\n")
            return header + body + "\n"
        }
    }

    static func fileName(for session: TranscriptSession, format: TranscriptExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let time = formatter.string(from: session.startedAt)
        return "transcript_\(time).\(format.rawValue)"
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
