import CryptoKit
import Foundation

public struct ModelDownloadProgress: Sendable {
    public var descriptorID: String
    public var downloadedBytes: Int64
    public var totalBytes: Int64?

    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1.0, Double(downloadedBytes) / Double(totalBytes))
    }

    public init(descriptorID: String, downloadedBytes: Int64, totalBytes: Int64?) {
        self.descriptorID = descriptorID
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
    }
}

public struct ModelInstallInspection: Sendable {
    public enum QuickStatus: String, Sendable, Equatable {
        case installed
        case sizeMismatch
        case partialOnly
        case notInstalled
    }

    public var descriptorID: String
    public var installedPath: URL
    public var partialPath: URL
    public var installedExists: Bool
    public var partialExists: Bool
    public var installedSizeBytes: Int64?
    public var expectedSizeBytes: Int64
    public var quickStatus: QuickStatus

    public init(
        descriptorID: String,
        installedPath: URL,
        partialPath: URL,
        installedExists: Bool,
        partialExists: Bool,
        installedSizeBytes: Int64?,
        expectedSizeBytes: Int64,
        quickStatus: QuickStatus
    ) {
        self.descriptorID = descriptorID
        self.installedPath = installedPath
        self.partialPath = partialPath
        self.installedExists = installedExists
        self.partialExists = partialExists
        self.installedSizeBytes = installedSizeBytes
        self.expectedSizeBytes = expectedSizeBytes
        self.quickStatus = quickStatus
    }
}

public struct ModelVerificationResult: Sendable {
    public var descriptorID: String
    public var isValid: Bool
    public var reason: String
    public var checkedAt: Date

    public init(descriptorID: String, isValid: Bool, reason: String, checkedAt: Date = Date()) {
        self.descriptorID = descriptorID
        self.isValid = isValid
        self.reason = reason
        self.checkedAt = checkedAt
    }
}

public struct ModelCleanupResult: Sendable {
    public var descriptorID: String
    public var removedInstalled: Bool
    public var removedPartial: Bool

    public init(descriptorID: String, removedInstalled: Bool, removedPartial: Bool) {
        self.descriptorID = descriptorID
        self.removedInstalled = removedInstalled
        self.removedPartial = removedPartial
    }
}

public final class ModelDownloadManager: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (ModelDownloadProgress) -> Void

    private let fileManager: FileManager
    private let session: URLSession
    private let overrideModelsRootURL: URL?

    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        modelsRootURL: URL? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.overrideModelsRootURL = modelsRootURL
    }

    public func modelsDirectory() throws -> URL {
        let folder: URL
        if let overrideModelsRootURL {
            folder = overrideModelsRootURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            folder = appSupport
                .appendingPathComponent("SayIt", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public func localPath(for descriptor: LocalModelDescriptor) throws -> URL {
        let base = try modelsDirectory()
        return base
            .appendingPathComponent(descriptor.engine.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.name)
    }

    public func partialPath(for descriptor: LocalModelDescriptor) throws -> URL {
        try localPath(for: descriptor).appendingPathExtension("part")
    }

    public func inspect(_ descriptor: LocalModelDescriptor) throws -> ModelInstallInspection {
        let installedPath = try localPath(for: descriptor)
        let partialPath = installedPath.appendingPathExtension("part")

        let installedExists = fileManager.fileExists(atPath: installedPath.path)
        let partialExists = fileManager.fileExists(atPath: partialPath.path)
        let installedSize = installedExists ? (try? fileSize(installedPath)) : nil

        let quickStatus: ModelInstallInspection.QuickStatus
        if installedExists {
            if descriptor.sizeBytes > 0, let installedSize, installedSize != descriptor.sizeBytes {
                quickStatus = .sizeMismatch
            } else {
                quickStatus = .installed
            }
        } else if partialExists {
            quickStatus = .partialOnly
        } else {
            quickStatus = .notInstalled
        }

        return ModelInstallInspection(
            descriptorID: descriptor.id,
            installedPath: installedPath,
            partialPath: partialPath,
            installedExists: installedExists,
            partialExists: partialExists,
            installedSizeBytes: installedSize,
            expectedSizeBytes: descriptor.sizeBytes,
            quickStatus: quickStatus
        )
    }

    public func verify(_ descriptor: LocalModelDescriptor) throws -> ModelVerificationResult {
        let installedPath = try localPath(for: descriptor)
        let exists = fileManager.fileExists(atPath: installedPath.path)
        guard exists else {
            return ModelVerificationResult(descriptorID: descriptor.id, isValid: false, reason: "missing")
        }

        let size = try fileSize(installedPath)
        if descriptor.sizeBytes > 0, size != descriptor.sizeBytes {
            return ModelVerificationResult(descriptorID: descriptor.id, isValid: false, reason: "size_mismatch")
        }

        if !descriptor.sha256.isEmpty {
            let actual = try checksum(installedPath)
            if actual.caseInsensitiveCompare(descriptor.sha256) != .orderedSame {
                return ModelVerificationResult(descriptorID: descriptor.id, isValid: false, reason: "checksum_mismatch")
            }
        }

        return ModelVerificationResult(descriptorID: descriptor.id, isValid: true, reason: "ok")
    }

    @discardableResult
    public func cleanupArtifacts(_ descriptor: LocalModelDescriptor, removeInstalled: Bool) throws -> ModelCleanupResult {
        let installedPath = try localPath(for: descriptor)
        let partialPath = installedPath.appendingPathExtension("part")
        var removedInstalled = false
        var removedPartial = false

        if fileManager.fileExists(atPath: partialPath.path) {
            try? fileManager.removeItem(at: partialPath)
            removedPartial = true
        }

        if removeInstalled, fileManager.fileExists(atPath: installedPath.path) {
            try? fileManager.removeItem(at: installedPath)
            removedInstalled = true
        }

        if let base = try? modelsDirectory() {
            try? removeEmptyParents(from: installedPath.deletingLastPathComponent(), stopAt: base)
        }

        return ModelCleanupResult(descriptorID: descriptor.id, removedInstalled: removedInstalled, removedPartial: removedPartial)
    }

    public func download(
        _ descriptor: LocalModelDescriptor,
        progress: ProgressHandler? = nil
    ) async throws -> URL {
        let destination = try localPath(for: descriptor)
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        // Reuse existing verified file when possible.
        if fileManager.fileExists(atPath: destination.path) {
            if try validateFile(at: destination, for: descriptor) {
                return destination
            }
            try? fileManager.removeItem(at: destination)
        }

        let partial = destination.appendingPathExtension("part")
        let existingBytes = (try? fileSize(partial)) ?? 0

        try await resumeDownload(
            descriptor: descriptor,
            destination: destination,
            partial: partial,
            resumeBytes: max(0, existingBytes),
            progress: progress
        )

        guard try validateFile(at: destination, for: descriptor) else {
            throw SayItError.storage("Model validation failed for \(descriptor.name)")
        }
        return destination
    }

    public func remove(_ descriptor: LocalModelDescriptor, recycle: Bool = true) throws {
        let path = try localPath(for: descriptor)
        let partialPath = path.appendingPathExtension("part")

        if fileManager.fileExists(atPath: partialPath.path) {
            try? fileManager.removeItem(at: partialPath)
        }

        if fileManager.fileExists(atPath: path.path) {
            if recycle {
                do {
                    _ = try fileManager.trashItem(at: path, resultingItemURL: nil)
                } catch {
                    try fileManager.removeItem(at: path)
                }
            } else {
                try fileManager.removeItem(at: path)
            }
        }

        if let base = try? modelsDirectory() {
            try? removeEmptyParents(from: path.deletingLastPathComponent(), stopAt: base)
        }
    }

    public func listInstalled() throws -> [URL] {
        let root = try modelsDirectory()
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files
    }

    private func resumeDownload(
        descriptor: LocalModelDescriptor,
        destination: URL,
        partial: URL,
        resumeBytes: Int64,
        progress: ProgressHandler?
    ) async throws {
        var request = URLRequest(url: descriptor.remoteURL)
        if resumeBytes > 0 {
            request.setValue("bytes=\(resumeBytes)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SayItError.network("Failed to download model \(descriptor.name): no HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            throw SayItError.network("Failed to download model \(descriptor.name): HTTP \(http.statusCode)")
        }

        // Server may ignore range and return full body (200). Restart from scratch.
        if resumeBytes > 0 && http.statusCode != 206 {
            if fileManager.fileExists(atPath: partial.path) {
                try? fileManager.removeItem(at: partial)
            }
            try await resumeDownload(
                descriptor: descriptor,
                destination: destination,
                partial: partial,
                resumeBytes: 0,
                progress: progress
            )
            return
        }

        if !fileManager.fileExists(atPath: partial.path) {
            fileManager.createFile(atPath: partial.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: partial)
        defer {
            try? handle.close()
        }

        if resumeBytes > 0 {
            try handle.seekToEnd()
        } else {
            try handle.truncate(atOffset: 0)
            try handle.seek(toOffset: 0)
        }

        let totalBytes = expectedTotalBytes(httpResponse: http, resumeBytes: resumeBytes)
        var written = resumeBytes
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        var lastEmitTime = Date.distantPast
        let emit: () -> Void = {
            progress?(ModelDownloadProgress(descriptorID: descriptor.id, downloadedBytes: written, totalBytes: totalBytes))
        }

        emit()
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if Date().timeIntervalSince(lastEmitTime) >= 0.15 {
                    emit()
                    lastEmitTime = Date()
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        emit()

        if descriptor.sizeBytes > 0, written < descriptor.sizeBytes {
            throw SayItError.storage("Downloaded model size is smaller than expected for \(descriptor.name)")
        }

        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: partial, to: destination)
    }

    private func expectedTotalBytes(httpResponse: HTTPURLResponse, resumeBytes: Int64) -> Int64? {
        if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
           let total = parseContentRangeTotal(contentRange)
        {
            return total
        }

        let contentLength = httpResponse.expectedContentLength
        guard contentLength >= 0 else { return nil }
        if httpResponse.statusCode == 206 {
            return resumeBytes + contentLength
        }
        return contentLength
    }

    private func parseContentRangeTotal(_ value: String) -> Int64? {
        // Example: "bytes 0-1023/4096"
        guard let slash = value.lastIndex(of: "/") else { return nil }
        let total = value[value.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        guard total != "*", let number = Int64(total) else { return nil }
        return number
    }

    private func validateFile(at url: URL, for descriptor: LocalModelDescriptor) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        let size = try fileSize(url)
        if descriptor.sizeBytes > 0, size != descriptor.sizeBytes {
            return false
        }

        if !descriptor.sha256.isEmpty {
            let actual = try checksum(url)
            guard actual.caseInsensitiveCompare(descriptor.sha256) == .orderedSame else {
                return false
            }
        }

        return true
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw SayItError.storage("Cannot read file size: \(url.path)")
        }
        return Int64(size)
    }

    private func checksum(_ url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw SayItError.storage("Cannot open file for checksum: \(url.path)")
        }

        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 {
                let message = stream.streamError?.localizedDescription ?? "checksum read failed"
                throw SayItError.storage(message)
            }
            if read == 0 {
                break
            }
            hasher.update(data: Data(buffer[0..<read]))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func removeEmptyParents(from start: URL, stopAt stopURL: URL) throws {
        var current = start.standardizedFileURL
        let stop = stopURL.standardizedFileURL

        while current.path.hasPrefix(stop.path), current.path != stop.path {
            let contents = try fileManager.contentsOfDirectory(atPath: current.path)
            if !contents.isEmpty {
                return
            }
            try fileManager.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }
}
