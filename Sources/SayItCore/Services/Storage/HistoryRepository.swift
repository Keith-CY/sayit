import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class HistoryRepository {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func createSession(_ session: TranscriptSession) throws {
        let sql = "INSERT OR REPLACE INTO sessions(id, source, app_bundle_id, locale, started_at, ended_at) VALUES(?, ?, ?, ?, ?, ?);"
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, session.id.uuidString)
            bindText(stmt, index: 2, session.source)
            bindOptionalText(stmt, index: 3, session.appBundleID)
            bindText(stmt, index: 4, session.locale)
            sqlite3_bind_double(stmt, 5, session.startedAt.timeIntervalSince1970)
            if let endedAt = session.endedAt {
                sqlite3_bind_double(stmt, 6, endedAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to insert session")
            }
        }
    }

    public func finishSession(id: UUID, endedAt: Date = Date()) throws {
        let sql = "UPDATE sessions SET ended_at = ? WHERE id = ?;"
        try store.withStatement(sql) { stmt in
            sqlite3_bind_double(stmt, 1, endedAt.timeIntervalSince1970)
            bindText(stmt, index: 2, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to update session end time")
            }
        }
    }

    public func addSegment(_ segment: TranscriptSegment) throws {
        let sql = "INSERT OR REPLACE INTO segments(id, session_id, sequence, start_ms, end_ms, raw_text, final_text, provider, latency_ms, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, segment.id.uuidString)
            bindText(stmt, index: 2, segment.sessionID.uuidString)
            sqlite3_bind_int(stmt, 3, Int32(segment.sequence))
            sqlite3_bind_int(stmt, 4, Int32(segment.startMs))
            sqlite3_bind_int(stmt, 5, Int32(segment.endMs))
            bindText(stmt, index: 6, segment.rawText)
            bindText(stmt, index: 7, segment.finalText)
            bindText(stmt, index: 8, segment.provider)
            sqlite3_bind_int(stmt, 9, Int32(segment.latencyMs))
            sqlite3_bind_double(stmt, 10, segment.createdAt.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to insert segment")
            }
        }

        let cleanupFTSSQL = "DELETE FROM segments_fts WHERE segment_id = ?;"
        try store.withStatement(cleanupFTSSQL) { stmt in
            bindText(stmt, index: 1, segment.id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to cleanup FTS segment")
            }
        }

        let ftsSQL = "INSERT INTO segments_fts(segment_id, session_id, raw_text, final_text) VALUES(?, ?, ?, ?);"
        try store.withStatement(ftsSQL) { stmt in
            bindText(stmt, index: 1, segment.id.uuidString)
            bindText(stmt, index: 2, segment.sessionID.uuidString)
            bindText(stmt, index: 3, segment.rawText)
            bindText(stmt, index: 4, segment.finalText)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to insert FTS segment")
            }
        }
    }

    public func savePipelineRun(_ run: PipelineRunRecord) throws {
        let sql = "INSERT INTO pipeline_runs(id, session_id, segment_id, stage_id, stage_type, before_text, after_text, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?);"
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, run.id.uuidString)
            bindText(stmt, index: 2, run.sessionID.uuidString)
            bindText(stmt, index: 3, run.segmentID.uuidString)
            bindText(stmt, index: 4, run.stageID.uuidString)
            bindText(stmt, index: 5, run.stageType.rawValue)
            bindText(stmt, index: 6, run.beforeText)
            bindText(stmt, index: 7, run.afterText)
            sqlite3_bind_double(stmt, 8, run.createdAt.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to insert pipeline run")
            }
        }
    }

    public func saveFallbackEvent(_ event: FallbackEvent) throws {
        let sql = "INSERT INTO fallback_events(id, from_provider, to_provider, reason, status_code, latency_ms, created_at) VALUES(?, ?, ?, ?, ?, ?, ?);"
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, event.id.uuidString)
            bindText(stmt, index: 2, event.fromProvider)
            bindText(stmt, index: 3, event.toProvider)
            bindText(stmt, index: 4, event.reason)
            if let statusCode = event.statusCode {
                sqlite3_bind_int(stmt, 5, Int32(statusCode))
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            sqlite3_bind_int(stmt, 6, Int32(event.latencyMs))
            sqlite3_bind_double(stmt, 7, event.timestamp.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to insert fallback event")
            }
        }
    }

    public func saveExportRecord(_ export: ExportRecord) throws {
        let sql = "INSERT INTO exports(id, session_id, format, path, created_at) VALUES(?, ?, ?, ?, ?);"
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, export.id.uuidString)
            bindText(stmt, index: 2, export.sessionID.uuidString)
            bindText(stmt, index: 3, export.format.rawValue)
            bindText(stmt, index: 4, export.path)
            sqlite3_bind_double(stmt, 5, export.createdAt.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to insert export")
            }
        }
    }

    public func saveAudioAsset(_ asset: AudioAssetRecord) throws {
        let sql = "INSERT OR REPLACE INTO audio_assets(id, session_id, path, duration_ms, sample_rate, created_at) VALUES(?, ?, ?, ?, ?, ?);"
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, asset.id.uuidString)
            bindText(stmt, index: 2, asset.sessionID.uuidString)
            bindText(stmt, index: 3, asset.path)
            sqlite3_bind_int(stmt, 4, Int32(asset.durationMs))
            sqlite3_bind_int(stmt, 5, Int32(asset.sampleRate))
            sqlite3_bind_double(stmt, 6, asset.createdAt.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to insert audio asset")
            }
        }
    }

    public func listAudioAssets(sessionID: UUID) throws -> [AudioAssetRecord] {
        let sql = "SELECT id, session_id, path, duration_ms, sample_rate, created_at FROM audio_assets WHERE session_id = ? ORDER BY created_at DESC;"
        var assets: [AudioAssetRecord] = []
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, sessionID.uuidString)
            while sqlite3_step(stmt) == SQLITE_ROW {
                assets.append(
                    AudioAssetRecord(
                        id: UUID(uuidString: string(stmt, index: 0)) ?? UUID(),
                        sessionID: UUID(uuidString: string(stmt, index: 1)) ?? sessionID,
                        path: string(stmt, index: 2),
                        durationMs: Int(sqlite3_column_int(stmt, 3)),
                        sampleRate: Int(sqlite3_column_int(stmt, 4)),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                    )
                )
            }
        }
        return assets
    }

    public func latestAudioAsset(sessionID: UUID) throws -> AudioAssetRecord? {
        try listAudioAssets(sessionID: sessionID).first
    }

    public func deleteAudioAsset(id: UUID) throws {
        let sql = "DELETE FROM audio_assets WHERE id = ?;"
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to delete audio asset")
            }
        }
    }

    public func deleteSession(id: UUID) throws {
        let cleanupFTS = "DELETE FROM segments_fts WHERE session_id = ?;"
        try store.withStatement(cleanupFTS) { stmt in
            bindText(stmt, index: 1, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to cleanup session FTS entries")
            }
        }

        let sql = "DELETE FROM sessions WHERE id = ?;"
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storageError("Failed to delete session")
            }
        }
    }

    public func listSessions(limit: Int = 100) throws -> [TranscriptSession] {
        let sql = "SELECT id, source, app_bundle_id, locale, started_at, ended_at FROM sessions ORDER BY started_at DESC LIMIT ?;"
        var sessions: [TranscriptSession] = []

        try store.withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = UUID(uuidString: string(stmt, index: 0)) ?? UUID()
                let source = string(stmt, index: 1)
                let appBundleID = optionalString(stmt, index: 2)
                let locale = string(stmt, index: 3)
                let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                let endedAt: Date?
                if sqlite3_column_type(stmt, 5) == SQLITE_NULL {
                    endedAt = nil
                } else {
                    endedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                }
                sessions.append(
                    TranscriptSession(id: id, source: source, appBundleID: appBundleID, locale: locale, startedAt: startedAt, endedAt: endedAt)
                )
            }
        }

        return sessions
    }

    public func listSessionSummaries(limit: Int = 100) throws -> [SessionSummary] {
        let sql = """
        SELECT
            s.id,
            s.source,
            s.app_bundle_id,
            s.locale,
            s.started_at,
            s.ended_at,
            COUNT(seg.id) AS segment_count,
            (
                SELECT seg2.final_text
                FROM segments seg2
                WHERE seg2.session_id = s.id
                ORDER BY seg2.sequence DESC
                LIMIT 1
            ) AS preview_text
        FROM sessions s
        LEFT JOIN segments seg ON seg.session_id = s.id
        GROUP BY s.id, s.source, s.app_bundle_id, s.locale, s.started_at, s.ended_at
        ORDER BY s.started_at DESC
        LIMIT ?;
        """

        var summaries: [SessionSummary] = []
        try store.withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = UUID(uuidString: string(stmt, index: 0)) ?? UUID()
                let source = string(stmt, index: 1)
                let appBundleID = optionalString(stmt, index: 2)
                let locale = string(stmt, index: 3)
                let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                let endedAt: Date?
                if sqlite3_column_type(stmt, 5) == SQLITE_NULL {
                    endedAt = nil
                } else {
                    endedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                }
                let count = Int(sqlite3_column_int(stmt, 6))
                let preview = optionalString(stmt, index: 7)
                let session = TranscriptSession(
                    id: id,
                    source: source,
                    appBundleID: appBundleID,
                    locale: locale,
                    startedAt: startedAt,
                    endedAt: endedAt
                )
                summaries.append(SessionSummary(session: session, segmentCount: count, previewText: preview))
            }
        }
        return summaries
    }

    public func listSegments(sessionID: UUID) throws -> [TranscriptSegment] {
        let sql = "SELECT id, session_id, sequence, start_ms, end_ms, raw_text, final_text, provider, latency_ms, created_at FROM segments WHERE session_id = ? ORDER BY sequence ASC;"
        var segments: [TranscriptSegment] = []

        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, sessionID.uuidString)
            while sqlite3_step(stmt) == SQLITE_ROW {
                segments.append(
                    TranscriptSegment(
                        id: UUID(uuidString: string(stmt, index: 0)) ?? UUID(),
                        sessionID: UUID(uuidString: string(stmt, index: 1)) ?? sessionID,
                        sequence: Int(sqlite3_column_int(stmt, 2)),
                        startMs: Int(sqlite3_column_int(stmt, 3)),
                        endMs: Int(sqlite3_column_int(stmt, 4)),
                        rawText: string(stmt, index: 5),
                        finalText: string(stmt, index: 6),
                        provider: string(stmt, index: 7),
                        latencyMs: Int(sqlite3_column_int(stmt, 8)),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
                    )
                )
            }
        }

        return segments
    }

    public func searchSegments(query: String, limit: Int = 50) throws -> [TranscriptSegment] {
        let sql = """
        SELECT s.id, s.session_id, s.sequence, s.start_ms, s.end_ms, s.raw_text, s.final_text, s.provider, s.latency_ms, s.created_at
        FROM segments_fts f
        JOIN segments s ON s.id = f.segment_id
        WHERE segments_fts MATCH ?
        LIMIT ?;
        """

        var segments: [TranscriptSegment] = []
        try store.withStatement(sql) { stmt in
            bindText(stmt, index: 1, query)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                segments.append(
                    TranscriptSegment(
                        id: UUID(uuidString: string(stmt, index: 0)) ?? UUID(),
                        sessionID: UUID(uuidString: string(stmt, index: 1)) ?? UUID(),
                        sequence: Int(sqlite3_column_int(stmt, 2)),
                        startMs: Int(sqlite3_column_int(stmt, 3)),
                        endMs: Int(sqlite3_column_int(stmt, 4)),
                        rawText: string(stmt, index: 5),
                        finalText: string(stmt, index: 6),
                        provider: string(stmt, index: 7),
                        latencyMs: Int(sqlite3_column_int(stmt, 8)),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
                    )
                )
            }
        }

        return segments
    }

    private func bindText(_ stmt: OpaquePointer, index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, NSString(string: value).utf8String, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ stmt: OpaquePointer, index: Int32, _ value: String?) {
        if let value {
            bindText(stmt, index: index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func string(_ stmt: OpaquePointer, index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    private func optionalString(_ stmt: OpaquePointer, index: Int32) -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return string(stmt, index: index)
    }

    private func storageError(_ message: String) -> SayItError {
        .storage(message)
    }
}
