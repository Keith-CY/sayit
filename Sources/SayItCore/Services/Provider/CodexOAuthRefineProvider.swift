import Foundation

public final class CodexOAuthRefineProvider: RefineProvider {
    public let id = "codex_oauth"

    private let keychain: KeychainStore
    private let oauthManager: CodexOAuthManager?
    private let endpoint: URL

    public init(
        keychain: KeychainStore,
        oauthManager: CodexOAuthManager? = nil,
        endpoint: URL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
    ) {
        self.keychain = keychain
        self.oauthManager = oauthManager
        self.endpoint = endpoint
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        let accessToken = try await resolveAccessToken()

        let accountID = try keychain.get("codex_account_id")
        let started = Date()

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        urlRequest.setValue("sayit", forHTTPHeaderField: "originator")
        if let accountID {
            urlRequest.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }

        let payload = CodexResponsesRequest(
            model: "gpt-5-codex",
            input: [.init(role: "user", content: [.init(kind: "input_text", text: request.text)])],
            instructions: "Polish transcript by removing fillers and improving sentence structure while keeping original intent.",
            stream: false,
            store: false
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SayItError.network("No HTTP response from Codex OAuth endpoint")
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                let refreshedToken = try? await refreshFromCodexAuthFileIfPossible()
                if let refreshedToken, !refreshedToken.isEmpty, refreshedToken != accessToken {
                    return try await refineWithExplicitToken(request: request, accessToken: refreshedToken, accountID: accountID)
                }
            }
            if http.statusCode == 401 || http.statusCode == 429 || http.statusCode >= 500 {
                throw ProviderHTTPError(providerID: id, statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
            }
            throw SayItError.network("Codex OAuth refine failed with status \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(CodexResponsesResponse.self, from: data)
        let text = decoded.outputText ?? request.text
        let latency = Int(Date().timeIntervalSince(started) * 1000)

        return RefineResult(text: text, provider: id, latencyMs: latency)
    }

    private func refineWithExplicitToken(
        request: RefineRequest,
        accessToken: String,
        accountID: String?
    ) async throws -> RefineResult {
        let started = Date()
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        urlRequest.setValue("sayit", forHTTPHeaderField: "originator")
        if let accountID {
            urlRequest.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }

        let payload = CodexResponsesRequest(
            model: "gpt-5-codex",
            input: [.init(role: "user", content: [.init(kind: "input_text", text: request.text)])],
            instructions: "Polish transcript by removing fillers and improving sentence structure while keeping original intent.",
            stream: false,
            store: false
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SayItError.network("No HTTP response from Codex OAuth endpoint")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 429 || http.statusCode >= 500 {
                throw ProviderHTTPError(providerID: id, statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
            }
            throw SayItError.network("Codex OAuth refine failed with status \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(CodexResponsesResponse.self, from: data)
        let text = decoded.outputText ?? request.text
        let latency = Int(Date().timeIntervalSince(started) * 1000)
        return RefineResult(text: text, provider: id, latencyMs: latency)
    }

    private func resolveAccessToken() async throws -> String {
        if let accessToken = try keychain.get("codex_access_token"), !accessToken.isEmpty {
            return accessToken
        }

        if let imported = try? await refreshFromCodexAuthFileIfPossible(), !imported.isEmpty {
            return imported
        }

        throw SayItError.authentication("Missing Codex OAuth access token")
    }

    private func refreshFromCodexAuthFileIfPossible() async throws -> String? {
        if let oauthManager {
            _ = try await oauthManager.syncFromDefaultAuthFile()
            let token = try keychain.get("codex_access_token")
            if let token, !token.isEmpty {
                return token
            }
        }

        guard let snapshot = try CodexAuthImporter.importFromDefaultLocations() else {
            return nil
        }
        if let access = snapshot.codexAccessToken, !access.isEmpty {
            try keychain.set(access, for: "codex_access_token")
        }
        if let refresh = snapshot.codexRefreshToken, !refresh.isEmpty {
            try keychain.set(refresh, for: "codex_refresh_token")
        }
        if let account = snapshot.codexAccountID, !account.isEmpty {
            try keychain.set(account, for: "codex_account_id")
        }
        return snapshot.codexAccessToken
    }
}

private struct CodexResponsesRequest: Encodable {
    struct Input: Encodable {
        struct Content: Encodable {
            let kind: String
            let text: String

            enum CodingKeys: String, CodingKey {
                case kind = "type"
                case text
            }
        }

        let role: String
        let content: [Content]
    }

    let model: String
    let input: [Input]
    let instructions: String
    let stream: Bool
    let store: Bool
}

private struct CodexResponsesResponse: Decodable {
    let outputText: String?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
    }
}
