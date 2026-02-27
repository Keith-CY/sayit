import Foundation

public struct FasterWhisperSTTProvider: STTProvider {
    public let id = "faster_whisper"

    private static let commandTemplateEnvKey = "SAYIT_FASTER_WHISPER_COMMAND"
    private static let modelEnvKey = "SAYIT_FASTER_WHISPER_MODEL"
    private static let pythonEnvKey = "SAYIT_FASTER_WHISPER_PYTHON"

    public init() {}

    public func startStreaming(config: STTStreamConfig) async throws -> AsyncThrowingStream<STTEvent, Error> {
        _ = config
        return AsyncThrowingStream { continuation in
            continuation.yield(STTEvent(kind: .started, text: ""))

            // Keep live mode focused on stable capture. We transcribe once after stop
            // from the full session recording handled in LiveTranscriptionViewModel.
            let loopTask = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: 200_000_000)
                    } catch is CancellationError {
                        break
                    } catch {
                        break
                    }
                }
                continuation.yield(STTEvent(kind: .ended, text: ""))
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                loopTask.cancel()
            }
        }
    }

    public func transcribeFile(url: URL, config: STTFileConfig) async throws -> [TranscriptSegment] {
        let started = Date()
        let modelName = resolveModelName()
        let transcript = try await LocalCommandTranscriber.run(
            providerID: id,
            fileURL: url,
            locale: config.locale,
            templateEnvKey: Self.commandTemplateEnvKey,
            defaultCommands: defaultCommands(modelName: modelName)
        )

        let lines = transcript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            throw SayItError.unavailable("faster-whisper returned empty transcript")
        }

        let latencyMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
        return lines.enumerated().map { index, line in
            TranscriptSegment(
                sessionID: UUID(),
                sequence: index,
                startMs: 0,
                endMs: 0,
                rawText: line,
                finalText: line,
                provider: id,
                latencyMs: latencyMs
            )
        }
    }

    private func resolveModelName() -> String {
        let env = ProcessInfo.processInfo.environment
        if let raw = env[Self.modelEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        return "small"
    }

    private func defaultCommands(modelName: String) -> [LocalCommandTranscriber.CommandSpec] {
        pythonExecutables().map { executable in
            LocalCommandTranscriber.CommandSpec(executable: executable) { fileURL, language in
                [
                    "-c",
                    Self.inlinePythonScript,
                    fileURL.path,
                    modelName,
                    language,
                ]
            }
        }
    }

    private func pythonExecutables() -> [String] {
        let env = ProcessInfo.processInfo.environment
        var executables: [String] = []
        if let override = env[Self.pythonEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            executables.append(override)
        }
        let fileManager = FileManager.default
        let home = NSHomeDirectory()
        let managedRuntimePython = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SayIt", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent(".venv-stt", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
            .path
        let venvCandidates = [
            managedRuntimePython,
            fileManager.currentDirectoryPath + "/.venv-stt/bin/python",
            home + "/.openclaw/workspace/.venv-stt/bin/python",
            "/root/.openclaw/workspace/.venv-stt/bin/python",
        ].compactMap { $0 }
        for candidate in venvCandidates where fileManager.isExecutableFile(atPath: candidate) {
            executables.append(candidate)
        }
        executables.append("python3")
        var seen: Set<String> = []
        return executables.filter { seen.insert($0).inserted }
    }

    private static let inlinePythonScript = """
import sys
from faster_whisper import WhisperModel

audio = sys.argv[1]
model_name = sys.argv[2]
language = sys.argv[3].strip() if len(sys.argv) > 3 else ""
if language in ("", "auto"):
    language = None

model = WhisperModel(model_name, device="cpu", compute_type="int8")
segments, _ = model.transcribe(audio, beam_size=3, vad_filter=True, language=language)
for segment in segments:
    text = (segment.text or "").strip()
    if text:
        print(f"[{segment.start:6.2f}-{segment.end:6.2f}] {text}")
"""
}
