import Foundation

public struct CodexAuthSnapshot: Sendable {
    public var openAIAPIKey: String?
    public var codexAccessToken: String?
    public var codexRefreshToken: String?
    public var codexAccountID: String?
    public var sourcePath: String

    public init(
        openAIAPIKey: String?,
        codexAccessToken: String?,
        codexRefreshToken: String?,
        codexAccountID: String?,
        sourcePath: String
    ) {
        self.openAIAPIKey = openAIAPIKey
        self.codexAccessToken = codexAccessToken
        self.codexRefreshToken = codexRefreshToken
        self.codexAccountID = codexAccountID
        self.sourcePath = sourcePath
    }
}

public enum CodexAuthImporter {
    public static func importFromDefaultLocations() throws -> CodexAuthSnapshot? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".codex/auth.json"),
            home.appendingPathComponent(".config/codex/auth.json"),
            home.appendingPathComponent("Library/Application Support/Codex/auth.json"),
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path.path) {
                return try importFrom(path: path)
            }
        }
        return nil
    }

    public static func importFrom(path: URL) throws -> CodexAuthSnapshot {
        let data = try Data(contentsOf: path)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SayItError.invalidConfiguration("Invalid auth json structure at \(path.path)")
        }

        let openAIAPIKey = root["OPENAI_API_KEY"] as? String
        let tokens = root["tokens"] as? [String: Any]
        let accessToken = tokens?["access_token"] as? String
        let refreshToken = tokens?["refresh_token"] as? String
        let accountID = tokens?["account_id"] as? String

        return CodexAuthSnapshot(
            openAIAPIKey: openAIAPIKey,
            codexAccessToken: accessToken,
            codexRefreshToken: refreshToken,
            codexAccountID: accountID,
            sourcePath: path.path
        )
    }
}
