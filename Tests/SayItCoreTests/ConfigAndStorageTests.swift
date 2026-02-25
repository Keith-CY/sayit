import Foundation
@testable import SayItCore
import SQLite3
import XCTest

final class ConfigAndStorageTests: XCTestCase {
    func testConfigLoadCreatesDefault() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempDir.appendingPathComponent("config.json")
        let manager = AppConfigManager(configURL: configURL)

        let config = try manager.load()

        XCTAssertEqual(config.stt.primary, "openai")
        XCTAssertEqual(config.stt.localDefault, "whisper")
        XCTAssertEqual(config.hotkey.keyCode, 49)
        XCTAssertEqual(config.hotkey.modifiers, 768)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))

        let raw = try String(contentsOf: configURL)
        XCTAssertTrue(raw.contains("\"local_default\""))
        XCTAssertTrue(raw.contains("\"pipeline\""))
        XCTAssertTrue(raw.contains("\"default_id\""))
        XCTAssertTrue(raw.contains("\"hotkey\""))
        XCTAssertTrue(raw.contains("\"key_code\""))
        XCTAssertTrue(raw.contains("\"modifiers\""))
    }

    func testSQLiteSchemaTablesExist() throws {
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        let store = try SQLiteStore(url: dbURL)

        let tableNames = try fetchTableNames(from: store)

        XCTAssertTrue(tableNames.contains("sessions"))
        XCTAssertTrue(tableNames.contains("segments"))
        XCTAssertTrue(tableNames.contains("pipeline_runs"))
        XCTAssertTrue(tableNames.contains("audio_assets"))
        XCTAssertTrue(tableNames.contains("fallback_events"))
        XCTAssertTrue(tableNames.contains("tts_assets"))
        XCTAssertTrue(tableNames.contains("exports"))
        XCTAssertTrue(tableNames.contains("segments_fts"))
    }

    func testHistoryRepositoryInsertAndSearch() async throws {
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        let store = try SQLiteStore(url: dbURL)
        let repo = HistoryRepository(store: store)

        let session = TranscriptSession(source: "test", locale: "en")
        try repo.createSession(session)

        let segment = TranscriptSegment(
            sessionID: session.id,
            sequence: 0,
            startMs: 0,
            endMs: 100,
            rawText: "foo bar",
            finalText: "foo bar",
            provider: "openai",
            latencyMs: 123
        )
        try repo.addSegment(segment)

        let sessions = try repo.listSessions(limit: 10)
        XCTAssertEqual(sessions.count, 1)

        let search = try repo.searchSegments(query: "foo", limit: 10)
        XCTAssertEqual(search.count, 1)
        XCTAssertEqual(search.first?.finalText, "foo bar")

        let summaries = try repo.listSessionSummaries(limit: 10)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.segmentCount, 1)
        XCTAssertEqual(summaries.first?.previewText, "foo bar")
    }

    func testHistoryRepositoryUpsertSegmentDoesNotDuplicateFTS() throws {
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        let store = try SQLiteStore(url: dbURL)
        let repo = HistoryRepository(store: store)

        let session = TranscriptSession(source: "test", locale: "en")
        try repo.createSession(session)

        let segmentID = UUID()
        let original = TranscriptSegment(
            id: segmentID,
            sessionID: session.id,
            sequence: 0,
            startMs: 0,
            endMs: 100,
            rawText: "alpha",
            finalText: "alpha beta",
            provider: "openai",
            latencyMs: 50
        )
        try repo.addSegment(original)

        var updated = original
        updated.finalText = "alpha gamma"
        try repo.addSegment(updated)

        let oldTerm = try repo.searchSegments(query: "beta", limit: 10)
        XCTAssertTrue(oldTerm.isEmpty)

        let newTerm = try repo.searchSegments(query: "gamma", limit: 10)
        XCTAssertEqual(newTerm.count, 1)
        XCTAssertEqual(newTerm.first?.id, segmentID)
    }

    func testHistoryRepositoryAudioAssets() throws {
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        let store = try SQLiteStore(url: dbURL)
        let repo = HistoryRepository(store: store)

        let session = TranscriptSession(source: "test", locale: "en")
        try repo.createSession(session)

        let first = AudioAssetRecord(
            sessionID: session.id,
            path: "/tmp/a.m4a",
            durationMs: 1200,
            sampleRate: 16000
        )
        try repo.saveAudioAsset(first)

        let second = AudioAssetRecord(
            sessionID: session.id,
            path: "/tmp/b.m4a",
            durationMs: 2400,
            sampleRate: 24000
        )
        try repo.saveAudioAsset(second)

        let listed = try repo.listAudioAssets(sessionID: session.id)
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(listed.first?.id, second.id)

        let latest = try repo.latestAudioAsset(sessionID: session.id)
        XCTAssertEqual(latest?.id, second.id)
    }

    func testHistoryRepositoryDeleteAudioAndSession() throws {
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        let store = try SQLiteStore(url: dbURL)
        let repo = HistoryRepository(store: store)

        let session = TranscriptSession(source: "test", locale: "en")
        try repo.createSession(session)

        let segment = TranscriptSegment(
            sessionID: session.id,
            sequence: 0,
            startMs: 0,
            endMs: 500,
            rawText: "hello world",
            finalText: "hello world",
            provider: "openai",
            latencyMs: 42
        )
        try repo.addSegment(segment)

        let asset = AudioAssetRecord(
            sessionID: session.id,
            path: "/tmp/delete-me.m4a",
            durationMs: 500,
            sampleRate: 24000
        )
        try repo.saveAudioAsset(asset)
        try repo.deleteAudioAsset(id: asset.id)
        XCTAssertTrue(try repo.listAudioAssets(sessionID: session.id).isEmpty)

        try repo.deleteSession(id: session.id)
        XCTAssertTrue(try repo.listSessions(limit: 20).isEmpty)
        XCTAssertTrue(try repo.listSegments(sessionID: session.id).isEmpty)
        XCTAssertTrue(try repo.searchSegments(query: "hello", limit: 20).isEmpty)
    }

    func testExportServiceJSON() async throws {
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        let store = try SQLiteStore(url: dbURL)
        let repo = HistoryRepository(store: store)
        let exportService = ExportService(repository: repo)

        let session = TranscriptSession(source: "test", locale: "en")
        try repo.createSession(session)

        try repo.addSegment(
            TranscriptSegment(
                sessionID: session.id,
                sequence: 0,
                startMs: 0,
                endMs: 100,
                rawText: "hello",
                finalText: "hello",
                provider: "openai",
                latencyMs: 20
            )
        )

        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let record = try await exportService.export(sessionID: session.id, format: .json, to: out)

        XCTAssertEqual(record.format, .json)
        let content = try String(contentsOf: out)
        XCTAssertTrue(content.contains("sessionID"))
    }

    func testDefaultPipelinesProvideStages() {
        let clean = DefaultPipelines.clean()
        XCTAssertFalse(clean.stages.isEmpty)

        let comment = DefaultPipelines.codeComment()
        XCTAssertEqual(comment.stages.last?.type, .codeCommentTemplate)
    }

    func testLegacyConfigMigration() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempDir.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let legacy: [String: Any] = [
            "locale": "en",
            "stt": [
                "primary": "whisper",
                "localDefault": "moonshine",
            ],
            "pipelineDefaultID": UUID().uuidString,
            "hotkey": [
                "keyCode": 49,
                "modifiers": 768,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy, options: [.prettyPrinted])
        try data.write(to: configURL)

        let manager = AppConfigManager(configURL: configURL)
        let config = try manager.load()

        XCTAssertEqual(config.locale, "en")
        XCTAssertEqual(config.stt.primary, "whisper")
        XCTAssertEqual(config.stt.localDefault, "moonshine")
        XCTAssertEqual(config.hotkey.modifiers, 768)
    }

    func testConfigSavePersistsHotkey() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempDir.appendingPathComponent("config.json")
        let manager = AppConfigManager(configURL: configURL)

        var config = try manager.load()
        config.hotkey.keyCode = 0
        config.hotkey.modifiers = 1048576
        try manager.save(config)

        let loaded = try manager.load()
        XCTAssertEqual(loaded.hotkey.keyCode, 0)
        XCTAssertEqual(loaded.hotkey.modifiers, 1048576)

        let raw = try String(contentsOf: configURL)
        XCTAssertTrue(raw.contains("\"key_code\" : 0"))
    }

    private func fetchTableNames(from store: SQLiteStore) throws -> Set<String> {
        var names: Set<String> = []
        try store.withStatement("SELECT name FROM sqlite_master WHERE type='table' OR type='view';") { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
                names.insert(String(cString: ptr))
            }
        }
        return names
    }
}
