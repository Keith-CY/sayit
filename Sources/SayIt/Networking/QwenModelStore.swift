import CryptoKit
import Foundation

/// A pinned, complete local installation; partial downloads never appear as installed.
struct QwenModelStore {
    struct ModelFile {
        let name: String
        let size: Int64
        var sha256: String?
    }

    static let repository = "mlx-community/Qwen3-ASR-1.7B-8bit"
    static let revision = "a8379a2e2f9e313c9292cdf1af4055ab56d50d55"
    static let files: [ModelFile] = [
        .init(name: "config.json", size: 7188),
        .init(name: "generation_config.json", size: 142),
        .init(name: "preprocessor_config.json", size: 330),
        .init(name: "tokenizer_config.json", size: 12487),
        .init(name: "vocab.json", size: 2776833),
        .init(name: "merges.txt", size: 1671853),
        .init(name: "chat_template.json", size: 1161),
        .init(name: "model.safetensors.index.json", size: 78968),
        .init(
            name: "model.safetensors",
            size: 2463307541,
            sha256: "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c"
        ),
    ]

    let directory: URL
    let session: URLSession

    init(directory: URL = Self.defaultDirectory, session: URLSession = .shared) {
        self.directory = directory
        self.session = session
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SayIt/Models/Qwen3-ASR-1.7B-8bit", isDirectory: true)
    }

    private var receiptURL: URL {
        self.directory.appendingPathComponent("sayit-installation.json")
    }

    private struct Receipt: Codable {
        let repository: String
        let revision: String
    }

    var isInstalled: Bool {
        guard let data = try? Data(contentsOf: self.receiptURL),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              receipt.repository == Self.repository,
              receipt.revision == Self.revision
        else { return false }
        return Self.files.allSatisfy { self.hasExpectedSize($0) }
    }

    func download(progressHandler: ((Double) -> Void)?) async throws {
        try Task.checkCancellation()
        try await QwenDownloadCoordinator.shared.run(directory: self.directory) {
            try await self.performDownload(progressHandler: progressHandler)
        }
    }

    private func performDownload(progressHandler: ((Double) -> Void)?) async throws {
        if self.isInstalled {
            progressHandler?(1)
            return
        }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let totalBytes = Double(Self.files.reduce(Int64(0)) { $0 + $1.size })
        var completedBytes: Int64 = 0

        for file in Self.files {
            try Task.checkCancellation()
            if !self.hasExpectedSize(file) {
                let completed = Double(completedBytes)
                let transfer = QwenFileDownload(configuration: self.session.configuration) { received in
                    progressHandler?(min(0.99, (completed + Double(received)) / totalBytes))
                }
                guard let url = URL(string: "https://huggingface.co/\(Self.repository)/resolve/\(Self.revision)/\(file.name)") else {
                    throw QwenModelError.invalidDownload(file.name)
                }
                let (temporaryURL, response) = try await transfer.download(from: url)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                guard let response = response as? HTTPURLResponse, (200 ... 299).contains(response.statusCode),
                      Self.size(at: temporaryURL) == file.size
                else { throw QwenModelError.invalidDownload(file.name) }
                try Self.verifyChecksum(file, at: temporaryURL)
                try Task.checkCancellation()
                let destination = self.directory.appendingPathComponent(file.name)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
            } else {
                // A prior attempt may have finished this file before cancellation.
                try Self.verifyChecksum(file, at: self.directory.appendingPathComponent(file.name))
            }
            completedBytes += file.size
            progressHandler?(min(0.99, Double(completedBytes) / totalBytes))
        }

        try Task.checkCancellation()
        let receipt = Receipt(repository: Self.repository, revision: Self.revision)
        try JSONEncoder().encode(receipt).write(to: self.receiptURL, options: .atomic)
        progressHandler?(1)
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: self.directory.path) {
            try FileManager.default.removeItem(at: self.directory)
        }
    }

    private func hasExpectedSize(_ file: ModelFile) -> Bool {
        Self.size(at: self.directory.appendingPathComponent(file.name)) == file.size
    }

    private static func size(at url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    private static func verifyChecksum(_ file: ModelFile, at url: URL) throws {
        guard let expected = file.sha256 else { return }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            digest.update(data: data)
        }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            // Remove the invalid completed file so Retry can fetch it again.
            try? FileManager.default.removeItem(at: url)
            throw QwenModelError.invalidDownload(file.name)
        }
    }
}

private actor QwenDownloadCoordinator {
    static let shared = QwenDownloadCoordinator()
    private var tasks: [URL: Task<Void, Error>] = [:]

    func run(directory: URL, operation: @escaping () async throws -> Void) async throws {
        let key = directory.standardizedFileURL
        if let existing = self.tasks[key] {
            try await existing.value
            return
        }
        let task = Task { try await operation() }
        self.tasks[key] = task
        defer { self.tasks[key] = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

private final class QwenFileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Int64) -> Void
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var cancelled = false
    private var lastProgressTime = Date.distantPast

    init(configuration: URLSessionConfiguration, onProgress: @escaping (Int64) -> Void) {
        self.configuration = configuration
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws -> (URL, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.start(url, continuation: continuation)
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func start(_ url: URL, continuation: CheckedContinuation<(URL, URLResponse), Error>) {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.cancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let session = URLSession(configuration: self.configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: url)
        self.task = task
        task.resume()
    }

    private func cancel() {
        self.lock.lock()
        self.cancelled = true
        let task = self.task
        self.lock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<(URL, URLResponse), Error>) {
        self.lock.lock()
        let continuation = self.continuation
        let session = self.session
        self.continuation = nil
        self.session = nil
        self.task = nil
        self.lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response else { throw URLError(.badServerResponse) }
            // URLSession removes its temporary file when this callback returns.
            let saved = FileManager.default.temporaryDirectory.appendingPathComponent("qwen-\(UUID().uuidString).download")
            try FileManager.default.moveItem(at: location, to: saved)
            self.finish(.success((saved, response)))
        } catch {
            self.finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { self.finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(self.lastProgressTime) >= 0.15 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        self.lastProgressTime = now
        self.onProgress(totalBytesWritten)
    }
}

enum QwenModelError: LocalizedError {
    case unsupportedHardware
    case notReady
    case invalidAudio
    case invalidDownload(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedHardware:
            return "Qwen3 ASR requires a Mac with Apple Silicon."
        case .notReady:
            return "Download and select Qwen3 ASR before transcribing."
        case .invalidAudio:
            return "The recording contains invalid audio samples."
        case let .invalidDownload(file):
            return "The Qwen3 ASR download is incomplete or damaged (\(file)). Please retry the download."
        }
    }
}
