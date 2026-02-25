import Foundation
import SQLite3

public final class SQLiteStore {
    private var db: OpaquePointer?
    private let url: URL

    public init(url: URL? = nil) throws {
        self.url = url ?? Self.defaultDatabaseURL()
        try open()
        try migrate()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public static func defaultDatabaseURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("SayIt", isDirectory: true)
        return folder.appendingPathComponent("history.sqlite")
    }

    private func open() throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            throw SayItError.storage("Failed to open sqlite: \(message)")
        }

        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
    }

    public func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SayItError.storage("SQL execution failed: \(message)\n\(sql)")
        }
    }

    public func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SayItError.storage("SQL prepare failed: \(message)\n\(sql)")
        }
        return statement
    }

    public func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                app_bundle_id TEXT,
                locale TEXT NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL
            );

            CREATE TABLE IF NOT EXISTS segments (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                sequence INTEGER NOT NULL,
                start_ms INTEGER NOT NULL,
                end_ms INTEGER NOT NULL,
                raw_text TEXT NOT NULL,
                final_text TEXT NOT NULL,
                provider TEXT NOT NULL,
                latency_ms INTEGER NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS pipeline_runs (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                segment_id TEXT NOT NULL,
                stage_id TEXT NOT NULL,
                stage_type TEXT NOT NULL,
                before_text TEXT NOT NULL,
                after_text TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
                FOREIGN KEY(segment_id) REFERENCES segments(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS audio_assets (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                path TEXT NOT NULL,
                duration_ms INTEGER NOT NULL,
                sample_rate INTEGER NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS fallback_events (
                id TEXT PRIMARY KEY,
                from_provider TEXT NOT NULL,
                to_provider TEXT NOT NULL,
                reason TEXT NOT NULL,
                status_code INTEGER,
                latency_ms INTEGER NOT NULL,
                created_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS tts_assets (
                id TEXT PRIMARY KEY,
                session_id TEXT,
                provider TEXT NOT NULL,
                voice TEXT NOT NULL,
                path TEXT,
                duration_ms INTEGER NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS exports (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                format TEXT NOT NULL,
                path TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS segments_fts USING fts5(
                segment_id UNINDEXED,
                session_id UNINDEXED,
                raw_text,
                final_text
            );
            """
        )
    }

    public func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    public func databaseURL() -> URL {
        url
    }
}

public extension SQLiteStore {
    func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try body(statement)
    }
}
