import Foundation

public struct OpenAIRefineProvider: RefineProvider {
    public let id = "openai_api"

    private let baseURL: URL
    private let apiKeyProvider: @Sendable () async throws -> String

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        apiKeyProvider: @escaping @Sendable () async throws -> String
    ) {
        self.baseURL = baseURL
        self.apiKeyProvider = apiKeyProvider
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        let started = Date()
        let apiKey = try await apiKeyProvider()

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionsRequest(
            model: "gpt-4.1-mini",
            messages: [
                .init(role: "system", content: "You polish transcribed text by removing fillers and improving structure while preserving meaning."),
                .init(role: "user", content: request.text)
            ]
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SayItError.network("No HTTP response from OpenAI refine API")
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 429 || http.statusCode >= 500 {
                throw ProviderHTTPError(providerID: id, statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
            }
            throw SayItError.network("OpenAI refine failed with status \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        let text = decoded.choices.first?.message.content ?? request.text
        let latency = Int(Date().timeIntervalSince(started) * 1000)

        return RefineResult(text: text, provider: id, latencyMs: latency)
    }
}

private struct ChatCompletionsRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}
