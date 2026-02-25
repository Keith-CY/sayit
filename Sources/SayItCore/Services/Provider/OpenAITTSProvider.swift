import Foundation

public struct OpenAITTSProvider: TTSProvider {
    public let id = "openai_tts"

    private let baseURL: URL
    private let apiKeyProvider: @Sendable () async throws -> String

    public init(baseURL: URL = URL(string: "https://api.openai.com/v1")!, apiKeyProvider: @escaping @Sendable () async throws -> String) {
        self.baseURL = baseURL
        self.apiKeyProvider = apiKeyProvider
    }

    public func synthesize(_ request: TTSRequest) async throws -> TTSAudio {
        let key = try await apiKeyProvider()

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("audio/speech"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body = TTSBody(model: "gpt-4o-mini-tts", voice: request.voice, input: request.text, format: request.format)
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SayItError.network("No HTTP response from OpenAI TTS API")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 429 || http.statusCode >= 500 {
                throw ProviderHTTPError(providerID: id, statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
            }
            throw SayItError.network("OpenAI TTS failed with status \(http.statusCode)")
        }

        return TTSAudio(data: data, format: request.format, durationMs: 0, provider: id)
    }
}

private struct TTSBody: Encodable {
    let model: String
    let voice: String
    let input: String
    let format: String

    enum CodingKeys: String, CodingKey {
        case model, voice, input
        case format = "response_format"
    }
}
