import CryptoKit
import Foundation
@testable import SayItCore
import XCTest

final class ModelDownloadManagerTests: XCTestCase {
    func testInspectNotInstalled() throws {
        let root = makeTempDirectory()
        let manager = ModelDownloadManager(modelsRootURL: root)
        let descriptor = makeDescriptor(name: "model.bin", size: 16, sha256: "")

        let inspection = try manager.inspect(descriptor)

        XCTAssertEqual(inspection.quickStatus, .notInstalled)
        XCTAssertFalse(inspection.installedExists)
        XCTAssertFalse(inspection.partialExists)
    }

    func testInspectPartialOnlyAndCleanup() throws {
        let root = makeTempDirectory()
        let manager = ModelDownloadManager(modelsRootURL: root)
        let descriptor = makeDescriptor(name: "model.bin", size: 16, sha256: "")
        let partial = try manager.partialPath(for: descriptor)

        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: partial.path, contents: Data([0x01, 0x02, 0x03]))

        let inspection = try manager.inspect(descriptor)
        XCTAssertEqual(inspection.quickStatus, .partialOnly)
        XCTAssertTrue(inspection.partialExists)

        let cleaned = try manager.cleanupArtifacts(descriptor, removeInstalled: false)
        XCTAssertTrue(cleaned.removedPartial)
        XCTAssertFalse(cleaned.removedInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testVerifySizeMismatch() throws {
        let root = makeTempDirectory()
        let manager = ModelDownloadManager(modelsRootURL: root)
        let descriptor = makeDescriptor(name: "model.bin", size: 100, sha256: "")
        let path = try manager.localPath(for: descriptor)

        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path.path, contents: Data(repeating: 0xAB, count: 10))

        let inspection = try manager.inspect(descriptor)
        XCTAssertEqual(inspection.quickStatus, .sizeMismatch)

        let verify = try manager.verify(descriptor)
        XCTAssertFalse(verify.isValid)
        XCTAssertEqual(verify.reason, "size_mismatch")
    }

    func testVerifySuccessWithChecksum() throws {
        let root = makeTempDirectory()
        let content = Data("abc123".utf8)
        let sha = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let descriptor = makeDescriptor(name: "model.bin", size: Int64(content.count), sha256: sha)
        let manager = ModelDownloadManager(modelsRootURL: root)
        let path = try manager.localPath(for: descriptor)

        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path.path, contents: content)

        let verify = try manager.verify(descriptor)
        XCTAssertTrue(verify.isValid)
        XCTAssertEqual(verify.reason, "ok")
    }

    private func makeDescriptor(name: String, size: Int64, sha256: String) -> LocalModelDescriptor {
        LocalModelDescriptor(
            engine: .whisper,
            name: name,
            remoteURL: URL(string: "https://example.com/\(name)")!,
            sha256: sha256,
            sizeBytes: size
        )
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
