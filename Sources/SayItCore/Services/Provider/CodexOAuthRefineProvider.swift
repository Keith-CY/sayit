import Foundation

public final class CodexOAuthRefineProvider: RefineProvider {
    public let id = "codex_oauth"

    private let endpoint: URL
    private let credentialCache: CodexAuthFileCredentialCache

    public init(
        keychain _: KeychainStore,
        oauthManager _: CodexOAuthManager? = nil,
        endpoint: URL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!,
        snapshotLoader: @escaping @Sendable () throws -> CodexAuthSnapshot? = {
            try CodexAuthImporter.importFromDefaultLocations()
        }
    ) {
        self.endpoint = endpoint
        self.credentialCache = CodexAuthFileCredentialCache(snapshotLoader: snapshotLoader)
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        let credentials = try await credentialCache.current()
        let started = Date()

        do {
            let text = try await refineText(requestText: request.text, credentials: credentials)
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            return RefineResult(text: text, provider: id, latencyMs: latency)
        } catch let error as ProviderHTTPError where error.statusCode == 401 {
            let refreshed = try await credentialCache.refresh()
            if refreshed.accessToken != credentials.accessToken {
                let text = try await refineText(requestText: request.text, credentials: refreshed)
                let latency = Int(Date().timeIntervalSince(started) * 1000)
                return RefineResult(text: text, provider: id, latencyMs: latency)
            }
            throw error
        }
    }

    private func refineText(
        requestText: String,
        credentials: CodexAuthFileCredentials
    ) async throws -> String {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        urlRequest.setValue("sayit", forHTTPHeaderField: "originator")
        if let accountID = credentials.accountID {
            urlRequest.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }

        let payload = CodexResponsesRequest(
            model: "gpt-5-codex",
            input: [.init(role: "user", content: [.init(kind: "input_text", text: requestText)])],
            instructions: "Polish transcript by removing fillers and improving sentence structure while keeping original intent.",
            stream: true,
            store: false
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SayItError.network("No HTTP response from Codex OAuth endpoint")
        }

        guard (200...299).contains(http.statusCode) else {
            let bodyData = try await Self.collectBody(from: bytes)
            let body = String(data: bodyData, encoding: .utf8) ?? ""
            if http.statusCode == 401 || http.statusCode == 429 || http.statusCode >= 500 {
                throw ProviderHTTPError(providerID: id, statusCode: http.statusCode, message: body)
            }
            throw SayItError.network("Codex OAuth refine failed with status \(http.statusCode): \(body)")
        }

        var state = CodexSSEParseState()
        for try await line in bytes.lines {
            try Self.ingestSSELine(line, state: &state)
            if state.didComplete {
                break
            }
        }

        return Self.finalizedRefineText(from: state, fallback: requestText)
    }

    static func ingestSSELine(_ line: String, state: inout CodexSSEParseState) throws {
        guard line.hasPrefix("data:") else { return }
        let rawData = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawData.isEmpty else { return }
        if rawData == "[DONE]" {
            state.didComplete = true
            return
        }

        guard let data = rawData.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        let type = payload["type"] as? String ?? ""
        switch type {
        case "response.output_text.delta":
            if let delta = payload["delta"] as? String {
                state.deltaText += delta
            }
        case "response.output_text.done":
            if let text = payload["text"] as? String, !text.isEmpty {
                state.doneText = text
            }
        case "response.completed":
            if let text = extractTextFromCompletedEvent(payload), !text.isEmpty {
                state.completedText = text
            }
            state.didComplete = true
        case "error", "response.failed":
            throw SayItError.network(extractErrorMessage(payload))
        default:
            break
        }
    }

    static func finalizedRefineText(from state: CodexSSEParseState, fallback: String) -> String {
        let text = state.doneText ?? state.completedText ?? state.deltaText
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return fallback
        }
        return text
    }

    private static func collectBody(from bytes: URLSession.AsyncBytes, limit: Int = 64 * 1024) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit {
                break
            }
        }
        return data
    }

    private static func extractTextFromCompletedEvent(_ payload: [String: Any]) -> String? {
        guard let response = payload["response"] as? [String: Any],
              let output = response["output"] as? [[String: Any]]
        else {
            return nil
        }

        for item in output {
            guard (item["type"] as? String) == "message",
                  let content = item["content"] as? [[String: Any]]
            else {
                continue
            }
            for part in content {
                guard (part["type"] as? String) == "output_text",
                      let text = part["text"] as? String,
                      !text.isEmpty
                else {
                    continue
                }
                return text
            }
        }
        return nil
    }

    private static func extractErrorMessage(_ payload: [String: Any]) -> String {
        if let error = payload["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty
        {
            return message
        }
        if let detail = payload["detail"] as? String, !detail.isEmpty {
            return detail
        }
        return "Codex OAuth stream error"
    }
}

actor CodexAuthFileCredentialCache {
    private let snapshotLoader: @Sendable () throws -> CodexAuthSnapshot?
    private var cached: CodexAuthFileCredentials?

    init(snapshotLoader: @escaping @Sendable () throws -> CodexAuthSnapshot?) {
        self.snapshotLoader = snapshotLoader
    }

    func current() throws -> CodexAuthFileCredentials {
        if let cached {
            return cached
        }
        return try refresh()
    }

    func refresh() throws -> CodexAuthFileCredentials {
        guard let snapshot = try snapshotLoader(),
              let accessToken = snapshot.codexAccessToken,
              !accessToken.isEmpty
        else {
            throw SayItError.authentication("Missing Codex OAuth access token in ~/.codex/auth.json")
        }

        let credentials = CodexAuthFileCredentials(
            accessToken: accessToken,
            accountID: snapshot.codexAccountID
        )
        cached = credentials
        return credentials
    }
}

struct CodexAuthFileCredentials: Sendable {
    let accessToken: String
    let accountID: String?
}

struct CodexSSEParseState: Sendable {
    var deltaText: String = ""
    var doneText: String?
    var completedText: String?
    var didComplete: Bool = false
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
