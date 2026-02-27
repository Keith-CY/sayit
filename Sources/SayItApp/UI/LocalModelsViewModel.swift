import Foundation
import SayItCore

@MainActor
final class LocalModelsViewModel: ObservableObject {
    @Published var installedNames: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var inspections: [String: ModelInstallInspection] = [:]
    @Published var verificationResults: [String: ModelVerificationResult] = [:]
    @Published var fasterWhisperPythonPath: String = "-"
    @Published var fasterWhisperRuntimeReady: Bool = false
    @Published var status: String = ""
    @Published var isBusy: Bool = false
    @Published var busyModelID: String?

    let catalog = ModelCatalog.defaults()
    private let runtime: SayItCoreRuntime?
    private static let runtimeTaskID = "__faster_whisper_runtime__"

    init(runtime: SayItCoreRuntime?) {
        self.runtime = runtime
        refresh()
    }

    func refresh() {
        guard let runtime else {
            status = "Model manager unavailable"
            return
        }

        do {
            var nextInspections: [String: ModelInstallInspection] = [:]
            var nextInstalledNames: Set<String> = []
            for descriptor in catalog {
                let inspection = try runtime.modelDownloadManager.inspect(descriptor)
                nextInspections[descriptor.id] = inspection
                if inspection.installedExists {
                    nextInstalledNames.insert(descriptor.name)
                }
            }
            inspections = nextInspections
            installedNames = nextInstalledNames
            refreshFasterWhisperRuntimePresence()
            status = "Installed: \(installedNames.count)"
        } catch {
            status = "Model refresh error: \(error.localizedDescription)"
        }
    }

    func isInstalled(_ descriptor: LocalModelDescriptor) -> Bool {
        installedNames.contains(descriptor.name)
    }

    func progress(for descriptor: LocalModelDescriptor) -> Double? {
        downloadProgress[descriptor.id]
    }

    func inspection(for descriptor: LocalModelDescriptor) -> ModelInstallInspection? {
        inspections[descriptor.id]
    }

    func installedPath(for descriptor: LocalModelDescriptor) -> String {
        inspection(for: descriptor)?.installedPath.path ?? "-"
    }

    func quickStatus(for descriptor: LocalModelDescriptor) -> ModelInstallInspection.QuickStatus {
        inspection(for: descriptor)?.quickStatus ?? .notInstalled
    }

    func verification(for descriptor: LocalModelDescriptor) -> ModelVerificationResult? {
        verificationResults[descriptor.id]
    }

    func isVerifying(_ descriptor: LocalModelDescriptor) -> Bool {
        busyModelID == descriptor.id && isBusy
    }

    func sizeLabel(for descriptor: LocalModelDescriptor) -> String {
        Self.byteFormatter.string(fromByteCount: descriptor.sizeBytes)
    }

    func runtimeRequirementHint(for descriptor: LocalModelDescriptor) -> String {
        switch descriptor.engine {
        case .whisper:
            return "Runtime: embedded whisper.cpp (in-process)"
        case .parakeet:
            return "Runtime: FluidAudio Parakeet CoreML (in-process, auto-download)"
        case .moonshine:
            return "Runtime: compatibility mode (Parakeet core -> Whisper fallback); archive is for native runtime prep"
        }
    }

    func toggle(_ descriptor: LocalModelDescriptor) async {
        if isInstalled(descriptor) {
            await remove(descriptor)
        } else {
            await download(descriptor)
        }
    }

    func download(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            _ = try await runtime.modelDownloadManager.download(descriptor) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.downloadProgress[progress.descriptorID] = progress.fractionCompleted
                    if let fraction = progress.fractionCompleted {
                        self.status = "Downloading \(descriptor.name) \(Int(fraction * 100))%"
                    } else {
                        self.status = "Downloading \(descriptor.name)"
                    }
                }
            }
            downloadProgress[descriptor.id] = 1
            status = "Downloaded \(descriptor.name)"
            verificationResults[descriptor.id] = ModelVerificationResult(descriptorID: descriptor.id, isValid: true, reason: "ok")
            refresh()
        } catch {
            downloadProgress[descriptor.id] = nil
            status = "Model operation failed: \(error.localizedDescription)"
        }
    }

    func remove(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            try runtime.modelDownloadManager.remove(descriptor)
            status = "Removed \(descriptor.name)"
            downloadProgress[descriptor.id] = nil
            verificationResults[descriptor.id] = nil
            refresh()
        } catch {
            status = "Model operation failed: \(error.localizedDescription)"
        }
    }

    func verify(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            let result = try runtime.modelDownloadManager.verify(descriptor)
            verificationResults[descriptor.id] = result
            status = "Verify \(descriptor.name): \(result.reason)"
            refresh()
        } catch {
            verificationResults[descriptor.id] = ModelVerificationResult(
                descriptorID: descriptor.id,
                isValid: false,
                reason: "verify_error"
            )
            status = "Verify failed: \(error.localizedDescription)"
            refresh()
        }
    }

    func retry(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            _ = try runtime.modelDownloadManager.cleanupArtifacts(descriptor, removeInstalled: true)
            verificationResults[descriptor.id] = nil
            downloadProgress[descriptor.id] = nil
            _ = try await runtime.modelDownloadManager.download(descriptor) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.downloadProgress[progress.descriptorID] = progress.fractionCompleted
                    if let fraction = progress.fractionCompleted {
                        self.status = "Retrying \(descriptor.name) \(Int(fraction * 100))%"
                    } else {
                        self.status = "Retrying \(descriptor.name)"
                    }
                }
            }
            downloadProgress[descriptor.id] = 1
            verificationResults[descriptor.id] = ModelVerificationResult(descriptorID: descriptor.id, isValid: true, reason: "ok")
            status = "Retry complete: \(descriptor.name)"
            refresh()
        } catch {
            status = "Retry failed: \(error.localizedDescription)"
            refresh()
        }
    }

    func cleanup(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            let inspection = try runtime.modelDownloadManager.inspect(descriptor)
            let removeInstalled = inspection.quickStatus == .sizeMismatch
            let cleaned = try runtime.modelDownloadManager.cleanupArtifacts(descriptor, removeInstalled: removeInstalled)
            verificationResults[descriptor.id] = nil
            downloadProgress[descriptor.id] = nil
            status = "Cleanup \(descriptor.name): installed=\(cleaned.removedInstalled) partial=\(cleaned.removedPartial)"
            refresh()
        } catch {
            status = "Cleanup failed: \(error.localizedDescription)"
            refresh()
        }
    }

    var isRuntimeBusy: Bool {
        isBusy && busyModelID == Self.runtimeTaskID
    }

    func installFasterWhisperRuntime() async {
        isBusy = true
        busyModelID = Self.runtimeTaskID
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            status = "Installing faster_whisper runtime..."
            let bootstrapPython = try resolveBootstrapPython()
            let runtimeRoot = managedRuntimeRoot()
            try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
            let venvPath = runtimeRoot.appendingPathComponent(".venv-stt", isDirectory: true).path
            let script = """
set -euo pipefail
BOOTSTRAP_PY=\(shellEscape(bootstrapPython))
VENV=\(shellEscape(venvPath))
"$BOOTSTRAP_PY" -m venv "$VENV"
"$VENV/bin/python" -m pip install --upgrade pip setuptools wheel
"$VENV/bin/python" -m pip install --upgrade faster-whisper
"""
            _ = try await runShell(script: script, timeoutSeconds: 1800)
            refreshFasterWhisperRuntimePresence()
            status = fasterWhisperRuntimeReady
                ? "Installed faster_whisper runtime (\(fasterWhisperPythonPath))"
                : "Runtime installation completed, but python path not detected"
        } catch {
            status = "Runtime install failed: \(error.localizedDescription)"
            refreshFasterWhisperRuntimePresence()
        }
    }

    func preloadFasterWhisperSmallModel() async {
        isBusy = true
        busyModelID = Self.runtimeTaskID
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            guard fasterWhisperRuntimeReady else {
                throw SayItError.unavailable("Runtime is not installed. Install runtime first.")
            }
            status = "Preloading faster_whisper small model..."
            let script = """
set -euo pipefail
PY=\(shellEscape(fasterWhisperPythonPath))
"$PY" - <<'PYCODE'
from faster_whisper import WhisperModel
WhisperModel("small", device="cpu", compute_type="int8")
print("small model ready")
PYCODE
"""
            _ = try await runShell(script: script, timeoutSeconds: 3600)
            status = "faster_whisper small model is ready"
        } catch {
            status = "Model preload failed: \(error.localizedDescription)"
        }
    }

    func diagnoseFasterWhisperRuntime() async {
        isBusy = true
        busyModelID = Self.runtimeTaskID
        defer { isBusy = false }
        defer { busyModelID = nil }

        var failures: [String] = []
        for candidate in runtimePythonCandidates() {
            guard let executable = resolveExecutable(candidate) else {
                failures.append("\(candidate): executable not found")
                continue
            }
            do {
                _ = try await runProcess(
                    executable: executable,
                    arguments: ["-c", "import faster_whisper; print('ok')"],
                    environment: ProcessInfo.processInfo.environment,
                    timeoutSeconds: 20
                )
                fasterWhisperPythonPath = executable
                fasterWhisperRuntimeReady = true
                status = "faster_whisper runtime ready: \(executable)"
                return
            } catch {
                failures.append("\(candidate): \(error.localizedDescription)")
            }
        }

        fasterWhisperRuntimeReady = false
        fasterWhisperPythonPath = "-"
        status = "Runtime unavailable: \(failures.joined(separator: " | "))"
    }

    private func refreshFasterWhisperRuntimePresence() {
        let managed = managedRuntimePythonPath().path
        if FileManager.default.isExecutableFile(atPath: managed) {
            fasterWhisperPythonPath = managed
            fasterWhisperRuntimeReady = true
            return
        }

        let env = ProcessInfo.processInfo.environment
        if let override = env["SAYIT_FASTER_WHISPER_PYTHON"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override)
        {
            fasterWhisperPythonPath = override
            fasterWhisperRuntimeReady = true
            return
        }

        fasterWhisperPythonPath = "-"
        fasterWhisperRuntimeReady = false
    }

    private func managedRuntimeRoot() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("SayIt", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
    }

    private func managedRuntimePythonPath() -> URL {
        managedRuntimeRoot()
            .appendingPathComponent(".venv-stt", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    private func runtimePythonCandidates() -> [String] {
        let env = ProcessInfo.processInfo.environment
        var values: [String] = []
        if let override = env["SAYIT_FASTER_WHISPER_PYTHON"]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            values.append(override)
        }
        values.append(managedRuntimePythonPath().path)
        values.append(FileManager.default.currentDirectoryPath + "/.venv-stt/bin/python")
        values.append(NSHomeDirectory() + "/.openclaw/workspace/.venv-stt/bin/python")
        values.append("/root/.openclaw/workspace/.venv-stt/bin/python")
        values.append("python3")
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func resolveBootstrapPython() throws -> String {
        if let resolved = resolveExecutable("python3") {
            return resolved
        }
        throw SayItError.unavailable("python3 is not available in PATH")
    }

    private func resolveExecutable(_ name: String) -> String? {
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

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private struct ProcessOutput {
        var stdout: String
        var stderr: String
    }

    private func runShell(script: String, timeoutSeconds: Double) async throws -> ProcessOutput {
        try await runProcess(
            executable: "/bin/zsh",
            arguments: ["-lc", script],
            environment: ProcessInfo.processInfo.environment,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: Double
    ) async throws -> ProcessOutput {
        try await withThrowingTaskGroup(of: ProcessOutput.self) { group in
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
                                continuation.resume(throwing: SayItError.unavailable(stderr.isEmpty ? stdout : stderr))
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
                let bounded = min(max(timeoutSeconds, 5), 7200)
                try await Task.sleep(nanoseconds: UInt64(bounded * 1_000_000_000))
                throw ProviderTimeoutError(providerID: "faster_whisper_runtime")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

private extension LocalModelsViewModel {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}
