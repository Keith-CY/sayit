import Foundation

enum LocalCommandTranscriber {
    static func run(
        providerID: String,
        fileURL: URL,
        locale: String,
        templateEnvKey: String,
        defaultCommands: [CommandSpec]
    ) async throws -> String {
        let env = ProcessInfo.processInfo.environment
        let language = normalizedLanguage(locale)

        if let template = env[templateEnvKey], !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let output = try await runTemplate(template, fileURL: fileURL, language: language)
            let cleaned = cleanTranscript(output)
            guard !cleaned.isEmpty else {
                throw SayItError.unavailable("\(providerID) command returned empty transcript")
            }
            return cleaned
        }

        var failures: [String] = []
        for command in defaultCommands {
            guard let executable = resolveExecutable(command.executable) else {
                failures.append("\(command.executable): executable not found")
                continue
            }
            let args = command.makeArgs(fileURL, language)
            do {
                let output = try await runProcessAllowingCancelledContext(
                    executable: executable,
                    arguments: args,
                    environment: env
                )
                let cleaned = cleanTranscript(output.stdout)
                if !cleaned.isEmpty {
                    return cleaned
                }
                failures.append("\(command.executable): command returned empty transcript")
            } catch {
                failures.append("\(command.executable): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            throw SayItError.unavailable("\(providerID) local command failed: \(failures.joined(separator: " | "))")
        }

        throw SayItError.unavailable(
            "\(providerID) local command is not configured. Set \(templateEnvKey) with placeholders {input} and {lang}"
        )
    }

    static func normalizedLanguage(_ locale: String) -> String {
        if locale.hasPrefix("zh") { return "zh" }
        if locale.hasPrefix("ja") { return "ja" }
        if locale.hasPrefix("en") { return "en" }
        return locale
    }

    static func defaultWhisperModelPath() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("SayIt", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("whisper", isDirectory: true)
            .appendingPathComponent("ggml-base.bin")
    }

    struct CommandSpec {
        let executable: String
        let makeArgs: (URL, String) -> [String]
    }

    struct ProcessOutput {
        let stdout: String
        let stderr: String
    }

    static func runTemplate(_ template: String, fileURL: URL, language: String) async throws -> String {
        let script = template
            .replacingOccurrences(of: "{input}", with: shellEscape(fileURL.path))
            .replacingOccurrences(of: "{lang}", with: shellEscape(language))
        let output = try await runProcessAllowingCancelledContext(
            executable: "/bin/zsh",
            arguments: ["-lc", script],
            environment: ProcessInfo.processInfo.environment
        )
        return output.stdout
    }

    static func resolveExecutable(_ name: String) -> String? {
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        for folder in path.split(separator: ":") {
            let candidate = "\(folder)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func runProcess(executable: String, arguments: [String], environment: [String: String]) async throws -> ProcessOutput {
        let timeoutSeconds = commandTimeoutSeconds(environment: environment)
        return try await withThrowingTaskGroup(of: ProcessOutput.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: executable)
                        process.arguments = arguments
                        process.environment = environment

                        let stdoutPipe = Pipe()
                        let stderrPipe = Pipe()
                        process.standardOutput = stdoutPipe
                        process.standardError = stderrPipe

                        do {
                            try process.run()
                            process.waitUntilExit()
                            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                            guard process.terminationStatus == 0 else {
                                continuation.resume(throwing: SayItError.unavailable("Local command failed: \(stderr.isEmpty ? stdout : stderr)"))
                                return
                            }
                            continuation.resume(returning: ProcessOutput(stdout: stdout, stderr: stderr))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }

            group.addTask {
                let nanos = UInt64(timeoutSeconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                throw ProviderTimeoutError(providerID: "local_command")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    static func runProcessAllowingCancelledContext(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessOutput {
        if Task.isCancelled {
            return try await Task.detached(priority: .userInitiated) {
                try await runProcess(executable: executable, arguments: arguments, environment: environment)
            }.value
        }
        return try await runProcess(executable: executable, arguments: arguments, environment: environment)
    }

    static func commandTimeoutSeconds(environment: [String: String]) -> Double {
        let raw = environment["SAYIT_LOCAL_COMMAND_TIMEOUT_SEC"] ?? ""
        let parsed = Double(raw) ?? 900
        // Keep bounds sane: enough for first-time model pull, avoid hanging forever.
        return min(max(parsed, 30), 7200)
    }

    static func cleanTranscript(_ text: String) -> String {
        let rawLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let lines = rawLines.compactMap { line -> String? in
            let lowercase = line.lowercased()
            if line.hasPrefix("[") && line.contains("]") {
                let parts = line.split(separator: "]", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    let cleaned = parts[1].trimmingCharacters(in: .whitespaces)
                    return cleaned.isEmpty ? nil : cleaned
                }
            }
            if lowercase.hasPrefix("whisper") || lowercase.contains("loading model") {
                return nil
            }
            if lowercase.hasPrefix("lang ") || lowercase.hasPrefix("language ") {
                return nil
            }
            return line
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
