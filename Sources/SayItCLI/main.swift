import Foundation
import SayItCore

@main
struct SayItCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            printHelp()
            return
        }

        let command = args[1]

        switch command {
        case "listen":
            let runtime = try SayItCoreRuntime()
            try await cmdListen(runtime: runtime, args: Array(args.dropFirst(2)))
        case "transcribe":
            let runtime = try SayItCoreRuntime()
            try await cmdTranscribe(runtime: runtime, args: Array(args.dropFirst(2)))
        case "refine":
            let runtime = try SayItCoreRuntime()
            try await cmdRefine(runtime: runtime, args: Array(args.dropFirst(2)))
        case "export":
            let runtime = try SayItCoreRuntime()
            try await cmdExport(runtime: runtime, args: Array(args.dropFirst(2)))
        case "models":
            try await cmdModels(args: Array(args.dropFirst(2)))
        case "pipeline":
            let runtime = try SayItCoreRuntime()
            try await cmdPipeline(runtime: runtime, args: Array(args.dropFirst(2)))
        case "providers":
            let runtime = try SayItCoreRuntime()
            try await cmdProviders(runtime: runtime, args: Array(args.dropFirst(2)))
        case "auth":
            let runtime = try SayItCoreRuntime()
            try await cmdAuth(runtime: runtime, args: Array(args.dropFirst(2)))
        case "config":
            let path = AppConfigManager.defaultConfigURL().path
            print(path)
        case "help", "-h", "--help":
            printHelp()
        default:
            throw SayItError.invalidConfiguration("Unknown command: \(command)")
        }
    }

    static func cmdListen(runtime: SayItCoreRuntime, args: [String]) async throws {
        let config = try runtime.configManager.load()
        let providerName = value(after: "--provider", in: args) ?? config.stt.primary
        let defaultLocale = config.locale
        let locale = value(after: "--locale", in: args) ?? defaultLocale
        let seconds = Int(value(after: "--seconds", in: args) ?? "") ?? 0
        let durationHint = seconds > 0 ? "\(seconds)s" : "until stopped (Ctrl+C)"

        let provider = runtime.sttProvider(for: providerName)

        let session = TranscriptSession(source: "cli_listen", locale: locale)
        try runtime.historyRepository.createSession(session)
        let sessionRecorder = SessionAudioRecorder()
        do {
            _ = try await sessionRecorder.startRecording()
        } catch {
            fputs("audio_asset_warning: \(error.localizedDescription)\n", stderr)
        }
        defer {
            if let tempURL = sessionRecorder.stopRecording() {
                defer { try? FileManager.default.removeItem(at: tempURL) }
                do {
                    let audioAsset = try runtime.audioAssetStore.importFile(tempURL, sessionID: session.id)
                    try runtime.historyRepository.saveAudioAsset(audioAsset)
                } catch {
                    fputs("audio_asset_warning: \(error.localizedDescription)\n", stderr)
                }
            }
        }

        print("Listening with \(provider.id), locale=\(locale), duration=\(durationHint)")
        print("Speak now...")

        var finalCount = 0
        let stream = try await provider.startStreaming(
            config: STTStreamConfig(sessionID: session.id, sampleRate: 24_000, channelCount: 1, locale: locale)
        )

        let deadline = seconds > 0 ? Date().addingTimeInterval(TimeInterval(seconds)) : nil
        for try await event in stream {
            switch event.kind {
            case .started:
                continue
            case .partial:
                if !event.text.isEmpty {
                    print("[partial] \(event.text)")
                }
            case .final:
                var segment = event.segment ?? TranscriptSegment(
                    sessionID: session.id,
                    sequence: finalCount,
                    startMs: 0,
                    endMs: 0,
                    rawText: event.text,
                    finalText: event.text,
                    provider: provider.id,
                    latencyMs: 0
                )
                segment.sessionID = session.id
                segment.sequence = finalCount
                finalCount += 1
                try runtime.historyRepository.addSegment(segment)
                print(segment.finalText)
            case .ended:
                break
            }

            if let deadline, Date() >= deadline {
                break
            }
        }

        try runtime.historyRepository.finishSession(id: session.id)
        print("Saved session \(session.id.uuidString) with \(finalCount) final segments")
    }

    static func cmdTranscribe(runtime: SayItCoreRuntime, args: [String]) async throws {
        guard let inputIndex = args.firstIndex(of: "--input"), args.count > inputIndex + 1 else {
            throw SayItError.invalidConfiguration("Usage: sayit transcribe --input <file> [--locale zh-Hans]")
        }

        let config = try runtime.configManager.load()
        let inputPath = args[inputIndex + 1]
        let locale = value(after: "--locale", in: args) ?? config.locale
        let inputURL = URL(fileURLWithPath: inputPath)
        let primaryProvider = runtime.sttProvider(for: value(after: "--provider", in: args) ?? config.stt.primary)
        let fallbackProvider = runtime.sttProvider(for: value(after: "--fallback", in: args) ?? config.stt.localDefault)
        let stateMachine = FallbackStateMachine(policy: config.fallbackPolicy)
        let pipeline = try selectPipeline(runtime: runtime, config: config, args: args)
        let pipelineExecutor = PipelineExecutor(refineProvider: runtime.refineProvider(for: config.refine.primary))

        let session = TranscriptSession(source: "cli_file", locale: locale)
        try runtime.historyRepository.createSession(session)
        defer { try? runtime.historyRepository.finishSession(id: session.id) }

        do {
            let audioAsset = try runtime.audioAssetStore.importFile(inputURL, sessionID: session.id)
            try runtime.historyRepository.saveAudioAsset(audioAsset)
        } catch {
            fputs("audio_asset_warning: \(error.localizedDescription)\n", stderr)
        }

        let (segments, fallbackEvent) = try await stateMachine.execute(
            primaryProvider: primaryProvider.id,
            fallbackProvider: fallbackProvider.id,
            operation: {
                try await primaryProvider.transcribeFile(url: inputURL, config: STTFileConfig(locale: locale))
            },
            fallback: {
                try await fallbackProvider.transcribeFile(url: inputURL, config: STTFileConfig(locale: locale))
            }
        )

        if let fallbackEvent {
            try runtime.historyRepository.saveFallbackEvent(fallbackEvent)
        }

        var finalized: [TranscriptSegment] = []
        for (index, raw) in segments.enumerated() {
            var segment = raw
            segment.sessionID = session.id
            segment.sequence = index
            var pipelineRuns: [PipelineRunRecord] = []
            if let pipeline {
                let (text, runs) = try await pipelineExecutor.run(
                    text: segment.finalText,
                    pipeline: pipeline,
                    sessionID: session.id,
                    segmentID: segment.id,
                    locale: locale
                )
                segment.finalText = text
                pipelineRuns = runs
            }
            try runtime.historyRepository.addSegment(segment)
            for run in pipelineRuns {
                do {
                    try runtime.historyRepository.savePipelineRun(run)
                } catch {
                    fputs("pipeline_run_warning: \(error.localizedDescription)\n", stderr)
                }
            }
            finalized.append(segment)
        }

        let output = finalized.map(\.finalText).joined(separator: "\n")
        print(output)
        if let fallbackEvent {
            fputs("fallback: \(fallbackEvent.fromProvider) -> \(fallbackEvent.toProvider) (\(fallbackEvent.reason))\n", stderr)
        }
    }

    static func cmdRefine(runtime: SayItCoreRuntime, args: [String]) async throws {
        let providerName = value(after: "--provider", in: args) ?? "codex"
        let text = readStdinText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw SayItError.invalidConfiguration("No input text provided on stdin")
        }

        let provider: RefineProvider = runtime.codexRefineProvider
        if providerName != "codex" {
            fputs("warning: only codex refine provider is enabled, using codex\n", stderr)
        }
        let result = try await provider.refine(RefineRequest(text: text))
        print(result.text)
    }

    static func cmdExport(runtime: SayItCoreRuntime, args: [String]) async throws {
        guard let sessionStr = value(after: "--session", in: args), let sessionID = UUID(uuidString: sessionStr) else {
            throw SayItError.invalidConfiguration("Usage: sayit export --session <uuid> --format txt|md|json [--output <path>]")
        }

        guard let formatValue = value(after: "--format", in: args), let format = ExportFormat(rawValue: formatValue) else {
            throw SayItError.invalidConfiguration("--format must be txt, md, or json")
        }

        let outputPath = value(after: "--output", in: args)
            ?? FileManager.default.currentDirectoryPath + "/session-\(sessionID.uuidString).\(format.rawValue)"
        let outputURL = URL(fileURLWithPath: outputPath)

        let record = try await runtime.exportService.export(sessionID: sessionID, format: format, to: outputURL)
        print(record.path)
    }

    static func cmdModels(args: [String]) async throws {
        guard let sub = args.first else {
            throw SayItError.invalidConfiguration("Usage: sayit models list|inspect|verify|cleanup|download|retry|remove")
        }

        let catalog = ModelCatalog.defaults()
        let downloadManager = ModelDownloadManager()
        let outputJSON = args.contains("--json")

        func descriptorByName(_ name: String) throws -> LocalModelDescriptor {
            guard let model = catalog.first(where: { $0.name == name }) else {
                throw SayItError.invalidConfiguration("Unknown model: \(name)")
            }
            return model
        }

        switch sub {
        case "list":
            var records: [ModelListRecord] = []
            for model in catalog {
                let inspection = try downloadManager.inspect(model)
                records.append(
                    ModelListRecord(
                        engine: model.engine.rawValue,
                        name: model.name,
                        status: inspection.quickStatus.rawValue
                    )
                )
            }
            if outputJSON {
                try printJSON(records)
            } else {
                for record in records {
                    print("\(record.engine):\(record.name)\t\(record.status)")
                }
            }
        case "inspect":
            let targets: [LocalModelDescriptor]
            if let name = value(after: "--name", in: args) {
                targets = [try descriptorByName(name)]
            } else {
                targets = catalog
            }

            var records: [ModelInspectRecord] = []
            for model in targets {
                let inspection = try downloadManager.inspect(model)
                let record = ModelInspectRecord(
                    engine: model.engine.rawValue,
                    name: model.name,
                    status: inspection.quickStatus.rawValue,
                    installedPath: inspection.installedPath.path,
                    partialPath: inspection.partialPath.path,
                    installedSize: inspection.installedSizeBytes,
                    expectedSize: inspection.expectedSizeBytes > 0 ? inspection.expectedSizeBytes : nil
                )
                records.append(record)
            }

            if outputJSON {
                try printJSON(records)
            } else {
                for record in records {
                    let installedSize = record.installedSize.map(String.init) ?? "-"
                    let expectedSize = record.expectedSize.map(String.init) ?? "-"
                    print(
                        """
                        \(record.engine):\(record.name)
                        \tstatus\t\(record.status)
                        \tinstalled_path\t\(record.installedPath)
                        \tpartial_path\t\(record.partialPath)
                        \tinstalled_size\t\(installedSize)
                        \texpected_size\t\(expectedSize)
                        """
                    )
                }
            }
        case "verify":
            let targets: [LocalModelDescriptor]
            if let name = value(after: "--name", in: args) {
                targets = [try descriptorByName(name)]
            } else {
                targets = catalog
            }

            var failed: [String] = []
            var records: [ModelVerifyRecord] = []
            for model in targets {
                let result = try downloadManager.verify(model)
                let status = result.isValid ? "ok" : "invalid"
                records.append(
                    ModelVerifyRecord(
                        engine: model.engine.rawValue,
                        name: model.name,
                        status: status,
                        reason: result.reason
                    )
                )
                if !result.isValid {
                    failed.append("\(model.name):\(result.reason)")
                }
            }

            if outputJSON {
                try printJSON(records)
            } else {
                for record in records {
                    print("\(record.engine):\(record.name)\t\(record.status)\t\(record.reason)")
                }
            }

            if !failed.isEmpty {
                throw SayItError.unavailable("Model verify failed: \(failed.joined(separator: ", "))")
            }
        case "download":
            guard let name = value(after: "--name", in: args) else {
                throw SayItError.invalidConfiguration("Usage: sayit models download --name <model-name>")
            }
            let model = try descriptorByName(name)
            let path = try await downloadManager.download(model) { progress in
                guard let fraction = progress.fractionCompleted else { return }
                let percent = Int(fraction * 100)
                fputs("\rdownloading \(model.name): \(percent)%", stderr)
            }
            fputs("\n", stderr)
            print(path.path)
        case "retry":
            guard let name = value(after: "--name", in: args) else {
                throw SayItError.invalidConfiguration("Usage: sayit models retry --name <model-name>")
            }
            let model = try descriptorByName(name)
            _ = try downloadManager.cleanupArtifacts(model, removeInstalled: true)
            let path = try await downloadManager.download(model) { progress in
                guard let fraction = progress.fractionCompleted else { return }
                let percent = Int(fraction * 100)
                fputs("\rretrying \(model.name): \(percent)%", stderr)
            }
            fputs("\n", stderr)
            print(path.path)
        case "cleanup":
            let removeInstalled = args.contains("--remove-installed")
            let targets: [LocalModelDescriptor]
            if let name = value(after: "--name", in: args) {
                targets = [try descriptorByName(name)]
            } else if args.contains("--all") {
                targets = catalog
            } else {
                throw SayItError.invalidConfiguration("Usage: sayit models cleanup --name <model-name> [--remove-installed] | --all [--remove-installed]")
            }

            var records: [ModelCleanupRecord] = []
            for model in targets {
                let result = try downloadManager.cleanupArtifacts(model, removeInstalled: removeInstalled)
                records.append(
                    ModelCleanupRecord(
                        engine: model.engine.rawValue,
                        name: model.name,
                        removedInstalled: result.removedInstalled,
                        removedPartial: result.removedPartial
                    )
                )
            }

            if outputJSON {
                try printJSON(records)
            } else {
                for record in records {
                    print("\(record.engine):\(record.name)\tremoved_installed=\(record.removedInstalled)\tremoved_partial=\(record.removedPartial)")
                }
            }
        case "remove":
            guard let name = value(after: "--name", in: args) else {
                throw SayItError.invalidConfiguration("Usage: sayit models remove --name <model-name>")
            }
            let model = try descriptorByName(name)
            try downloadManager.remove(model)
            print("removed \(name)")
        default:
            throw SayItError.invalidConfiguration("Unknown models subcommand: \(sub)")
        }
    }

    static func cmdPipeline(runtime: SayItCoreRuntime, args: [String]) async throws {
        guard let sub = args.first else {
            throw SayItError.invalidConfiguration("Usage: sayit pipeline list|set-default|import|remove|export-defaults")
        }

        switch sub {
        case "list":
            let config = try runtime.configManager.load()
            let pipelines = try runtime.pipelineStore.load()
            for pipeline in pipelines {
                let marker = (config.pipeline.defaultID == pipeline.id) ? "*" : " "
                print("\(marker)\t\(pipeline.id.uuidString)\t\(pipeline.name)\tstages=\(pipeline.stages.count)")
            }
        case "set-default":
            guard let idText = value(after: "--id", in: args), let id = UUID(uuidString: idText) else {
                throw SayItError.invalidConfiguration("Usage: sayit pipeline set-default --id <uuid>")
            }
            guard (try runtime.pipelineStore.find(id: id)) != nil else {
                throw SayItError.invalidConfiguration("Pipeline id not found: \(id.uuidString)")
            }
            var config = try runtime.configManager.load()
            config.pipeline.defaultID = id
            try runtime.configManager.save(config)
            print("default pipeline set: \(id.uuidString)")
        case "import":
            guard let filePath = value(after: "--file", in: args) else {
                throw SayItError.invalidConfiguration("Usage: sayit pipeline import --file <pipeline-json>")
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            var imported = 0
            if let pipeline = try? JSONDecoder().decode(TextPipeline.self, from: data) {
                try runtime.pipelineStore.upsert(pipeline)
                imported = 1
            } else if let pipelines = try? JSONDecoder().decode([TextPipeline].self, from: data) {
                for pipeline in pipelines {
                    try runtime.pipelineStore.upsert(pipeline)
                }
                imported = pipelines.count
            } else {
                throw SayItError.invalidConfiguration("Invalid pipeline JSON")
            }
            print("imported \(imported) pipeline(s)")
        case "remove":
            guard let idText = value(after: "--id", in: args), let id = UUID(uuidString: idText) else {
                throw SayItError.invalidConfiguration("Usage: sayit pipeline remove --id <uuid>")
            }
            try runtime.pipelineStore.remove(id: id)
            var config = try runtime.configManager.load()
            if config.pipeline.defaultID == id {
                let pipelines = try runtime.pipelineStore.load()
                config.pipeline.defaultID = pipelines.first?.id
                try runtime.configManager.save(config)
            }
            print("removed \(id.uuidString)")
        case "export-defaults":
            let outputPath = value(after: "--output", in: args)
                ?? FileManager.default.currentDirectoryPath + "/sayit-default-pipelines.json"
            let outputURL = URL(fileURLWithPath: outputPath)
            let data = try JSONEncoder.pretty.encode(DefaultPipelines.all())
            try data.write(to: outputURL, options: .atomic)
            print(outputURL.path)
        default:
            throw SayItError.invalidConfiguration("Unknown pipeline subcommand: \(sub)")
        }
    }

    static func cmdProviders(runtime: SayItCoreRuntime, args: [String]) async throws {
        guard args.first == "test" else {
            throw SayItError.invalidConfiguration("Usage: sayit providers test")
        }

        let providers = [
            runtime.fasterWhisperProvider.id,
            runtime.codexRefineProvider.id,
            runtime.systemTTSProvider.id,
        ]

        for id in providers {
            print("ok\t\(id)")
        }
    }

    static func cmdAuth(runtime: SayItCoreRuntime, args: [String]) async throws {
        guard let sub = args.first else {
            throw SayItError.invalidConfiguration("Usage: sayit auth import-codex|status-codex|login-codex|logout-codex")
        }

        switch sub {
        case "import-codex":
            let status = try await runtime.codexOAuthManager.syncFromDefaultAuthFile()
            print(status.statusLine)
        case "status-codex":
            let status = try await runtime.codexOAuthManager.status()
            print(status.statusLine)
            if let sourcePath = status.sourcePath, !sourcePath.isEmpty {
                print("auth_file\t\(sourcePath)")
            }
            if let refresh = status.lastRefresh {
                print("last_refresh\t\(refresh.ISO8601Format())")
            }
            print("has_access_token\t\(status.hasAccessToken)")
            print("has_refresh_token\t\(status.hasRefreshToken)")
        case "login-codex":
            let stream = await runtime.codexOAuthManager.startDeviceAuthFlow()
            for try await event in stream {
                switch event {
                case .output(let line):
                    print(line)
                case .challenge(let url, let code):
                    print("auth_url\t\(url.absoluteString)")
                    print("device_code\t\(code)")
                case .completed(let status):
                    print(status.statusLine)
                }
            }
        case "logout-codex":
            try await runtime.codexOAuthManager.logout()
            print("Codex OAuth logged out")
        default:
            throw SayItError.invalidConfiguration("Unknown auth subcommand: \(sub)")
        }
    }

    static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.count > index + 1 else {
            return nil
        }
        return args[index + 1]
    }

    static func selectPipeline(runtime: SayItCoreRuntime, config: AppConfig, args: [String]) throws -> TextPipeline? {
        let pipelines = try runtime.pipelineStore.load()
        guard !pipelines.isEmpty else { return nil }

        if let idText = value(after: "--pipeline-id", in: args), let id = UUID(uuidString: idText) {
            return pipelines.first(where: { $0.id == id })
        }

        if let selectedID = config.pipeline.defaultID, let selected = pipelines.first(where: { $0.id == selectedID }) {
            return selected
        }

        return pipelines.first
    }

    static func readStdinText() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func printHelp() {
        print(
            """
            sayit - SayIt CLI

            Commands:
              sayit listen [--provider faster_whisper] [--locale zh-Hans] [--seconds 20]
              sayit transcribe --input <file> [--locale zh-Hans]
              sayit refine [--provider codex] < stdin
              sayit export --session <uuid> --format txt|md|json [--output <path>]
              sayit models list [--json]
              sayit models inspect [--name <model-name>] [--json]
              sayit models verify [--name <model-name>] [--json]
              sayit models cleanup --name <model-name> [--remove-installed] [--json]
              sayit models cleanup --all [--remove-installed] [--json]
              sayit models download --name <model-name>
              sayit models retry --name <model-name>
              sayit models remove --name <model-name>
              sayit pipeline list|set-default|import|remove|export-defaults
              sayit providers test
              sayit auth import-codex|status-codex|login-codex|logout-codex
              sayit config
            """
        )
    }

    static func captureAudioToTempFile(seconds: Int) async throws -> URL {
        let recorder = AudioCaptureService()
        return try await recorder.recordFor(seconds: TimeInterval(seconds))
    }

    static func printJSON<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder.pretty.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SayItError.storage("Failed to encode JSON output")
        }
        print(text)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private struct ModelInspectRecord: Encodable {
    let engine: String
    let name: String
    let status: String
    let installedPath: String
    let partialPath: String
    let installedSize: Int64?
    let expectedSize: Int64?
}

private struct ModelListRecord: Encodable {
    let engine: String
    let name: String
    let status: String
}

private struct ModelVerifyRecord: Encodable {
    let engine: String
    let name: String
    let status: String
    let reason: String
}

private struct ModelCleanupRecord: Encodable {
    let engine: String
    let name: String
    let removedInstalled: Bool
    let removedPartial: Bool
}
