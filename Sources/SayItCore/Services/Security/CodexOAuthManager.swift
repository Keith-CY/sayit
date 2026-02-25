import Foundation

public struct CodexOAuthStatus: Sendable {
    public var isLoggedIn: Bool
    public var statusLine: String
    public var sourcePath: String?
    public var lastRefresh: Date?
    public var hasAccessToken: Bool
    public var hasRefreshToken: Bool
    public var accountID: String?

    public init(
        isLoggedIn: Bool,
        statusLine: String,
        sourcePath: String? = nil,
        lastRefresh: Date? = nil,
        hasAccessToken: Bool = false,
        hasRefreshToken: Bool = false,
        accountID: String? = nil
    ) {
        self.isLoggedIn = isLoggedIn
        self.statusLine = statusLine
        self.sourcePath = sourcePath
        self.lastRefresh = lastRefresh
        self.hasAccessToken = hasAccessToken
        self.hasRefreshToken = hasRefreshToken
        self.accountID = accountID
    }
}

public enum CodexOAuthEvent: Sendable {
    case output(String)
    case challenge(url: URL, code: String)
    case completed(CodexOAuthStatus)
}

public final actor CodexOAuthManager {
    private let keychain: KeychainStore
    private let executable: String
    private var activeLoginProcess: Process?

    public init(keychain: KeychainStore, executable: String = "codex") {
        self.keychain = keychain
        self.executable = executable
    }

    public func status() async throws -> CodexOAuthStatus {
        let result = try await runCodexCommand(args: ["login", "status"])
        if result.exitCode != 0 {
            let message = CodexOAuthParser.stripANSI(result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw SayItError.authentication(message.isEmpty ? "codex login status failed (\(result.exitCode))" : message)
        }
        let merged = [result.stdout, result.stderr]
            .joined(separator: "\n")
            .split(separator: "\n")
            .map { CodexOAuthParser.stripANSI(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("WARNING:") }

        let statusLine = merged.last ?? "Unknown"
        let isLoggedIn = CodexOAuthParser.isLoggedInStatus(statusLine)
        if let snapshot = try? CodexAuthImporter.importFromDefaultLocations() {
            let parsed = try? parseAuthMetadata(at: URL(fileURLWithPath: snapshot.sourcePath))
            return CodexOAuthStatus(
                isLoggedIn: isLoggedIn,
                statusLine: statusLine,
                sourcePath: snapshot.sourcePath,
                lastRefresh: parsed?.lastRefresh,
                hasAccessToken: !(snapshot.codexAccessToken ?? "").isEmpty,
                hasRefreshToken: !(snapshot.codexRefreshToken ?? "").isEmpty,
                accountID: snapshot.codexAccountID
            )
        }
        return CodexOAuthStatus(isLoggedIn: isLoggedIn, statusLine: statusLine)
    }

    public func syncFromDefaultAuthFile() async throws -> CodexOAuthStatus {
        guard let snapshot = try CodexAuthImporter.importFromDefaultLocations() else {
            throw SayItError.authentication("No codex auth file found")
        }
        try applySnapshotToKeychain(snapshot)
        let parsed = try parseAuthMetadata(at: URL(fileURLWithPath: snapshot.sourcePath))
        return CodexOAuthStatus(
            isLoggedIn: true,
            statusLine: "Imported from \(snapshot.sourcePath)",
            sourcePath: snapshot.sourcePath,
            lastRefresh: parsed.lastRefresh,
            hasAccessToken: !(snapshot.codexAccessToken ?? "").isEmpty,
            hasRefreshToken: !(snapshot.codexRefreshToken ?? "").isEmpty,
            accountID: snapshot.codexAccountID
        )
    }

    public func logout() async throws {
        let result = try await runCodexCommand(args: ["logout"])
        if result.exitCode != 0 {
            let message = CodexOAuthParser.stripANSI(result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw SayItError.authentication(message.isEmpty ? "codex logout failed (\(result.exitCode))" : message)
        }
        keychain.delete("codex_access_token")
        keychain.delete("codex_refresh_token")
        keychain.delete("codex_account_id")
    }

    public func startDeviceAuthFlow() -> AsyncThrowingStream<CodexOAuthEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: SayItError.unavailable("OAuth manager unavailable"))
                    return
                }
                await self.launchDeviceAuth(continuation: continuation)
            }

            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.cancelActiveLogin()
                }
            }
        }
    }

    public func cancelActiveLogin() {
        activeLoginProcess?.terminate()
        activeLoginProcess = nil
    }
}

private extension CodexOAuthManager {
    struct CommandResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    struct ParsedAuthMetadata {
        var lastRefresh: Date?
    }

    func launchDeviceAuth(
        continuation: AsyncThrowingStream<CodexOAuthEvent, Error>.Continuation
    ) async {
        guard activeLoginProcess == nil else {
            continuation.finish(throwing: SayItError.unavailable("Codex OAuth login already running"))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable, "login", "--device-auth"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let challengeState = ChallengeEmissionState()
        let outputHandler: @Sendable (Data) -> Void = { data in
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            let cleanChunk = CodexOAuthParser.stripANSI(chunk)

            for rawLine in cleanChunk.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                continuation.yield(.output(line))
            }

            if let url = CodexOAuthParser.firstURL(in: cleanChunk),
               let code = CodexOAuthParser.oneTimeCode(in: cleanChunk),
               challengeState.markIfFirst()
            {
                continuation.yield(.challenge(url: url, code: code))
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { file in
            outputHandler(file.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { file in
            outputHandler(file.availableData)
        }

        process.terminationHandler = { [weak self] process in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let remainingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let remainingErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            outputHandler(remainingOut)
            outputHandler(remainingErr)

            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: SayItError.unavailable("Codex OAuth manager unavailable"))
                    return
                }
                await self.onDeviceAuthTerminated(
                    exitCode: process.terminationStatus,
                    continuation: continuation
                )
            }
        }

        do {
            try process.run()
            activeLoginProcess = process
        } catch {
            continuation.finish(throwing: SayItError.unavailable("Failed to start codex login: \(error.localizedDescription)"))
        }
    }

    func onDeviceAuthTerminated(
        exitCode: Int32,
        continuation: AsyncThrowingStream<CodexOAuthEvent, Error>.Continuation
    ) async {
        activeLoginProcess = nil

        if exitCode == 0 {
            do {
                let status = try await syncFromDefaultAuthFile()
                continuation.yield(.completed(status))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            return
        }

        continuation.finish(throwing: SayItError.authentication("Codex device auth exited with status \(exitCode)"))
    }

    func applySnapshotToKeychain(_ snapshot: CodexAuthSnapshot) throws {
        if let key = snapshot.openAIAPIKey, !key.isEmpty {
            try keychain.set(key, for: "openai_api_key")
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
    }

    func parseAuthMetadata(at url: URL) throws -> ParsedAuthMetadata {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedAuthMetadata(lastRefresh: nil)
        }

        let lastRefresh: Date?
        if let raw = root["last_refresh"] as? String {
            lastRefresh = CodexOAuthParser.parseISO8601(raw)
        } else {
            lastRefresh = nil
        }
        return ParsedAuthMetadata(lastRefresh: lastRefresh)
    }

    func runCodexCommand(args: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                continuation.resume(returning: CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: SayItError.unavailable("Failed to execute codex command: \(error.localizedDescription)"))
            }
        }
    }
}

private final class ChallengeEmissionState: @unchecked Sendable {
    private var emitted = false
    private let lock = NSLock()

    func markIfFirst() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if emitted {
            return false
        }
        emitted = true
        return true
    }
}

enum CodexOAuthParser {
    static func stripANSI(_ text: String) -> String {
        let esc = "\u{001B}"
        return text.replacingOccurrences(
            of: "\(esc)\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }

    static func firstURL(in text: String) -> URL? {
        let pattern = #"https://[A-Za-z0-9\-\._~:/\?#\[\]@!\$&'\(\)\*\+,;=%]+"#
        guard let match = firstMatch(in: text, pattern: pattern) else { return nil }
        return URL(string: match)
    }

    static func oneTimeCode(in text: String) -> String? {
        firstMatch(in: text, pattern: #"\b[A-Z0-9]{4}-[A-Z0-9]{5,6}\b"#)
    }

    static func isLoggedInStatus(_ statusLine: String) -> Bool {
        let normalized = statusLine.lowercased()
        if normalized.contains("not logged in") || normalized.contains("logged out") {
            return false
        }
        return normalized.contains("logged in")
    }

    static func parseISO8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text)
        else {
            return nil
        }
        return String(text[matchRange])
    }
}
