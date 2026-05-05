import Foundation

actor SessionStore {
    private let directory: URL
    private let encoder = JSONEncoder()

    init(baseDirectory: URL) {
        self.directory = baseDirectory
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func saveCheckpoint(_ session: TranscriptSession) throws {
        try ensureDirectory()
        let url = directory.appendingPathComponent("session_\(session.id.uuidString).json")
        let data = try encoder.encode(session)
        try data.write(to: url, options: .atomic)
    }

    func appendChunk(sessionID: UUID, text: String) throws {
        try ensureDirectory()
        let url = directory.appendingPathComponent("session_\(sessionID.uuidString).log")
        let line = text + "\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }
}
