import AVFoundation
import Foundation

public struct OpenAISTTProvider: STTProvider {
    public let id = "openai"

    public struct Credential: Sendable {
        public enum Mode: Sendable {
            case apiKey
            case codexOAuth
        }

        public var token: String
        public var mode: Mode
        public var accountID: String?
        public var chatGPTBaseURL: String?

        public init(token: String, mode: Mode, accountID: String? = nil, chatGPTBaseURL: String? = nil) {
            self.token = token
            self.mode = mode
            self.accountID = accountID
            self.chatGPTBaseURL = chatGPTBaseURL
        }
    }

    private let credentialProvider: @Sendable () async throws -> Credential
    private let baseURL: URL

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        credentialProvider: @escaping @Sendable () async throws -> Credential
    ) {
        self.baseURL = baseURL
        self.credentialProvider = credentialProvider
    }

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        apiKeyProvider: @escaping @Sendable () async throws -> String
    ) {
        self.init(baseURL: baseURL) {
            let token = try await apiKeyProvider()
            return Credential(token: token, mode: .apiKey)
        }
    }

    public func startStreaming(config: STTStreamConfig) async throws -> AsyncThrowingStream<STTEvent, Error> {
        try await ensureMicrophonePermission()
        let credential = try await credentialProvider()
        let mode = Self.resolvedStreamingMode()
        if mode == .realtimeWebSocket && credential.mode == .apiKey {
            return try await startRealtimeStreaming(config: config, credential: credential)
        }
        return try await startChunkedStreaming(config: config, credential: credential)
    }

    public func transcribeFile(url: URL, config: STTFileConfig) async throws -> [TranscriptSegment] {
        let credential = try await credentialProvider()
        return try await transcribeFile(url: url, config: config, credential: credential)
    }

    private func startChunkedStreaming(config: STTStreamConfig, credential: Credential) async throws -> AsyncThrowingStream<STTEvent, Error> {
        return LocalChunkedSTTStreamer.start(providerID: id, config: config) { url, fileConfig in
            try await transcribeFile(url: url, config: fileConfig, credential: credential)
        }
    }

    private func startRealtimeStreaming(config: STTStreamConfig, credential: Credential) async throws -> AsyncThrowingStream<STTEvent, Error> {
        guard let wsURL = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            throw SayItError.invalidConfiguration("Invalid realtime websocket URL")
        }

        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        return AsyncThrowingStream { continuation in
            continuation.yield(STTEvent(kind: .started, text: ""))

            let webSocketTask = URLSession(configuration: .default).webSocketTask(with: request)
            let sender = OpenAIRealtimeWebSocketSender(task: webSocketTask)
            let microphone = MicrophonePCMStreamer(sampleRate: config.sampleRate, channelCount: config.channelCount)
            let resources = RealtimeStreamingResources(webSocketTask: webSocketTask, microphone: microphone)

            let streamTask = Task {
                do {
                    webSocketTask.resume()
                    try await sender.sendSessionUpdate(config: config)

                    try microphone.start { chunk in
                        if Task.isCancelled { return }
                        let sendTask = Task {
                            _ = try? await sender.sendAudioAppend(chunk)
                        }
                        resources.store(sendTask)
                    }

                    try await receiveRealtimeEvents(
                        task: webSocketTask,
                        config: config,
                        continuation: continuation
                    )

                    continuation.yield(STTEvent(kind: .ended, text: ""))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(STTEvent(kind: .ended, text: ""))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                await sender.commit()
                resources.stop()
            }

            resources.streamTask = streamTask
            continuation.onTermination = { @Sendable _ in
                resources.cancel()
            }
        }
    }

    private func transcribeFile(url: URL, config: STTFileConfig, credential: Credential) async throws -> [TranscriptSegment] {
        let request: URLRequest
        switch credential.mode {
        case .apiKey:
            request = try makeOpenAITranscribeRequest(fileURL: url, config: config, token: credential.token)
        case .codexOAuth:
            request = try makeChatGPTTranscribeRequest(fileURL: url, token: credential.token, accountID: credential.accountID, baseURL: credential.chatGPTBaseURL)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SayItError.network("No HTTP response from transcription API")
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 429 || http.statusCode >= 500 {
                throw ProviderHTTPError(providerID: id, statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
            }
            throw SayItError.network("Transcription failed with status \(http.statusCode)")
        }

        let payload = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let segment = TranscriptSegment(
            sessionID: UUID(),
            sequence: 0,
            startMs: 0,
            endMs: 0,
            rawText: text,
            finalText: text,
            provider: id,
            latencyMs: 0
        )
        return [segment]
    }

    private func makeOpenAITranscribeRequest(fileURL: URL, config: STTFileConfig, token: String) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeOpenAIMultipartBody(fileURL: fileURL, boundary: boundary, locale: config.locale)
        return request
    }

    private func makeChatGPTTranscribeRequest(fileURL: URL, token: String, accountID: String?, baseURL: String?) throws -> URLRequest {
        var request = URLRequest(url: Self.chatGPTTranscribeURL(baseURL: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let accountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines), !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeChatGPTMultipartBody(fileURL: fileURL, boundary: boundary)
        return request
    }

    private func receiveRealtimeEvents(
        task: URLSessionWebSocketTask,
        config: STTStreamConfig,
        continuation: AsyncThrowingStream<STTEvent, Error>.Continuation
    ) async throws {
        var partialByItem: [String: String] = [:]
        var orderedItemIDs: [String] = []
        var finalSequence = 0
        let startedAt = Date()

        while !Task.isCancelled {
            let message = try await task.receive()
            guard let event = OpenAIRealtimeServerEvent.parse(message) else { continue }

            switch event.type {
            case "input_audio_buffer.committed":
                guard let itemID = event.itemID, !orderedItemIDs.contains(itemID) else { continue }
                if let previous = event.previousItemID, let index = orderedItemIDs.firstIndex(of: previous) {
                    orderedItemIDs.insert(itemID, at: index + 1)
                } else {
                    orderedItemIDs.append(itemID)
                }

            case "conversation.item.input_audio_transcription.delta":
                guard let delta = event.delta else { continue }
                let itemID = event.itemID ?? "active"
                let updated = (partialByItem[itemID] ?? "") + delta
                partialByItem[itemID] = updated
                continuation.yield(STTEvent(kind: .partial, text: updated))

            case "conversation.item.input_audio_transcription.completed":
                let itemID = event.itemID ?? UUID().uuidString
                let text = event.transcript ?? partialByItem[itemID] ?? ""
                guard !text.isEmpty else { continue }

                let sequence: Int
                if let index = orderedItemIDs.firstIndex(of: itemID) {
                    sequence = index
                } else {
                    sequence = finalSequence
                    orderedItemIDs.append(itemID)
                }
                finalSequence = max(finalSequence, sequence + 1)

                let latency = Int(Date().timeIntervalSince(startedAt) * 1000)
                let segment = TranscriptSegment(
                    sessionID: config.sessionID,
                    sequence: sequence,
                    startMs: 0,
                    endMs: 0,
                    rawText: text,
                    finalText: text,
                    provider: id,
                    latencyMs: latency
                )
                partialByItem[itemID] = nil
                continuation.yield(STTEvent(kind: .final, text: text, segment: segment))

            case "error":
                let message = event.error?.message ?? "OpenAI realtime stream error"
                throw SayItError.network(message)

            default:
                continue
            }
        }
    }

    private func makeOpenAIMultipartBody(fileURL: URL, boundary: String, locale: String) throws -> Data {
        var data = Data()

        func append(_ value: String) {
            data.append(value.data(using: .utf8)!)
        }

        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL)

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("gpt-4o-transcribe\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        append("\(mapLanguageCode(from: locale))\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return data
    }

    private func makeChatGPTMultipartBody(fileURL: URL, boundary: String) throws -> Data {
        var data = Data()

        func append(_ value: String) {
            data.append(value.data(using: .utf8)!)
        }

        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL)

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return data
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "aif", "aiff":
            return "audio/aiff"
        case "webm":
            return "audio/webm"
        case "ogg":
            return "audio/ogg"
        case "flac":
            return "audio/flac"
        default:
            return "audio/mpeg"
        }
    }

    private func mapLanguageCode(from locale: String) -> String {
        if locale.hasPrefix("zh") { return "zh" }
        if locale.hasPrefix("ja") { return "ja" }
        if locale.hasPrefix("en") { return "en" }
        return locale
    }

    private func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { access in
                    continuation.resume(returning: access)
                }
            }
            guard granted else {
                throw SayItError.authentication("Microphone permission denied")
            }
        case .restricted, .denied:
            throw SayItError.authentication("Microphone permission is restricted or denied")
        @unknown default:
            throw SayItError.authentication("Unknown microphone authorization status")
        }
    }

    private static func resolvedStreamingMode() -> StreamingMode {
        let raw = ProcessInfo.processInfo.environment["SAYIT_OPENAI_STREAM_MODE"] ?? ""
        if raw.lowercased() == "realtime" {
            return .realtimeWebSocket
        }
        return .chunkedUpload
    }

    static func chatGPTTranscribeURL(baseURL: String?) -> URL {
        let normalized = normalizedChatGPTBaseURL(from: baseURL)
        return normalized.appendingPathComponent("transcribe")
    }

    static func normalizedChatGPTBaseURL(from rawBaseURL: String?) -> URL {
        let fallback = URL(string: "https://chatgpt.com/backend-api")!
        guard let rawBaseURL else { return fallback }
        let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var url = URL(string: trimmed) else { return fallback }

        // Keep path canonical and remove trailing slash segments.
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lower = path.lowercased()
        if lower.isEmpty {
            url.append(path: "backend-api")
        } else if !lower.contains("backend-api") {
            url.append(path: "backend-api")
        }
        return url
    }
}

private extension OpenAISTTProvider {
    enum StreamingMode {
        case chunkedUpload
        case realtimeWebSocket
    }
}

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
}

private struct OpenAIRealtimeServerEvent: Decodable {
    let type: String
    let itemID: String?
    let previousItemID: String?
    let delta: String?
    let transcript: String?
    let error: OpenAIRealtimeErrorPayload?

    enum CodingKeys: String, CodingKey {
        case type
        case itemID = "item_id"
        case previousItemID = "previous_item_id"
        case delta
        case transcript
        case error
    }

    static func parse(_ message: URLSessionWebSocketTask.Message) -> OpenAIRealtimeServerEvent? {
        let decoder = JSONDecoder()
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return nil }
            return try? decoder.decode(OpenAIRealtimeServerEvent.self, from: data)
        case .data(let data):
            return try? decoder.decode(OpenAIRealtimeServerEvent.self, from: data)
        @unknown default:
            return nil
        }
    }
}

private struct OpenAIRealtimeErrorPayload: Decodable {
    let code: String?
    let message: String?
}

private actor OpenAIRealtimeWebSocketSender {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func sendSessionUpdate(config: STTStreamConfig) async throws {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": config.sampleRate,
                        ],
                        "transcription": [
                            "model": "gpt-4o-transcribe",
                            "language": mapLanguageCode(from: config.locale),
                            "prompt": config.initialPrompt ?? "",
                        ],
                        "turn_detection": [
                            "type": "server_vad",
                        ],
                    ],
                ],
            ],
        ]
        try await sendJSON(payload)
    }

    func sendAudioAppend(_ audio: Data) async throws {
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": audio.base64EncodedString(),
        ]
        try await sendJSON(payload)
    }

    func commit() async {
        try? await sendJSON(["type": "input_audio_buffer.commit"])
    }

    private func sendJSON(_ payload: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SayItError.invalidConfiguration("Invalid JSON payload encoding")
        }
        try await task.send(.string(text))
    }

    private func mapLanguageCode(from locale: String) -> String {
        if locale.hasPrefix("zh") { return "zh" }
        if locale.hasPrefix("ja") { return "ja" }
        if locale.hasPrefix("en") { return "en" }
        return locale
    }
}

private final class RealtimeStreamingResources: @unchecked Sendable {
    var streamTask: Task<Void, Never>?

    private let webSocketTask: URLSessionWebSocketTask
    private let microphone: MicrophonePCMStreamer
    private var sendTasks: [Task<Void, Never>] = []
    private let lock = NSLock()

    init(webSocketTask: URLSessionWebSocketTask, microphone: MicrophonePCMStreamer) {
        self.webSocketTask = webSocketTask
        self.microphone = microphone
    }

    func store(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        sendTasks.append(task)
    }

    func cancel() {
        streamTask?.cancel()
        stop()
    }

    func stop() {
        microphone.stop()
        webSocketTask.cancel(with: .goingAway, reason: nil)
        lock.lock()
        let tasks = sendTasks
        sendTasks.removeAll()
        lock.unlock()
        for task in tasks {
            task.cancel()
        }
    }
}
