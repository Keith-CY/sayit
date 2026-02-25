@preconcurrency import AVFoundation
import Foundation

public final class AudioAssetStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let rootURL: URL

    public init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootURL = appSupport
                .appendingPathComponent("SayIt", isDirectory: true)
                .appendingPathComponent("audio-assets", isDirectory: true)
        }
    }

    public func importFile(_ sourceURL: URL, sessionID: UUID) throws -> AudioAssetRecord {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let sessionFolder = rootURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: sessionFolder, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let destination = sessionFolder.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try fileManager.copyItem(at: sourceURL, to: destination)

        let metadata = Self.readMetadata(url: destination)
        return AudioAssetRecord(
            sessionID: sessionID,
            path: destination.path,
            durationMs: metadata.durationMs,
            sampleRate: metadata.sampleRate
        )
    }

    public func makeRecordForExistingFile(_ fileURL: URL, sessionID: UUID) -> AudioAssetRecord {
        let metadata = Self.readMetadata(url: fileURL)
        return AudioAssetRecord(
            sessionID: sessionID,
            path: fileURL.path,
            durationMs: metadata.durationMs,
            sampleRate: metadata.sampleRate
        )
    }

    private static func readMetadata(url: URL) -> (durationMs: Int, sampleRate: Int) {
        var durationMs = 0
        var sampleRate = 0

        if let file = try? AVAudioFile(forReading: url) {
            let rate = file.processingFormat.sampleRate
            sampleRate = Int(rate)
            if rate > 0 {
                let seconds = Double(file.length) / rate
                if seconds.isFinite && seconds > 0 {
                    durationMs = Int(seconds * 1000)
                }
            }
        }

        return (durationMs, sampleRate)
    }
}
