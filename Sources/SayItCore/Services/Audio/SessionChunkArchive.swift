import Foundation

public enum SessionChunkArchive {
    private static let rootFolderName = "sayit-live-chunks"

    public static func archiveChunk(_ sourceURL: URL, sessionID: UUID) throws -> URL {
        let fileManager = FileManager.default
        let sessionFolder = try ensureSessionFolder(sessionID: sessionID, fileManager: fileManager)

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let archivedURL = sessionFolder.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try fileManager.copyItem(at: sourceURL, to: archivedURL)
        return archivedURL
    }

    public static func listChunks(sessionID: UUID) -> [URL] {
        let fileManager = FileManager.default
        let folder = sessionFolderURL(sessionID: sessionID, fileManager: fileManager)
        guard let files = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return leftDate < rightDate
        }
    }

    public static func clear(sessionID: UUID) {
        let fileManager = FileManager.default
        let folder = sessionFolderURL(sessionID: sessionID, fileManager: fileManager)
        try? fileManager.removeItem(at: folder)
    }

    private static func ensureSessionFolder(sessionID: UUID, fileManager: FileManager) throws -> URL {
        let folder = sessionFolderURL(sessionID: sessionID, fileManager: fileManager)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func sessionFolderURL(sessionID: UUID, fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(rootFolderName, isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }
}
