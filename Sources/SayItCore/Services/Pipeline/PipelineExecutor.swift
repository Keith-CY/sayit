import Foundation

public final class PipelineExecutor: @unchecked Sendable {
    private let refineProvider: RefineProvider?

    public init(refineProvider: RefineProvider? = nil) {
        self.refineProvider = refineProvider
    }

    public func run(
        text: String,
        pipeline: TextPipeline,
        sessionID: UUID,
        segmentID: UUID,
        locale: String
    ) async throws -> (text: String, runs: [PipelineRunRecord]) {
        guard pipeline.enabled else {
            return (text, [])
        }

        var current = text
        var runs: [PipelineRunRecord] = []

        for stage in pipeline.stages where stage.enabled {
            let before = current
            current = try await apply(stage: stage, text: current, sessionID: sessionID, locale: locale)
            let run = PipelineRunRecord(
                sessionID: sessionID,
                segmentID: segmentID,
                stageID: stage.id,
                stageType: stage.type,
                beforeText: before,
                afterText: current
            )
            runs.append(run)
        }

        return (current, runs)
    }

    private func apply(stage: PipelineStage, text: String, sessionID: UUID, locale: String) async throws -> String {
        switch stage.type {
        case .smartPunctuation:
            return smartPunctuation(text)
        case .fillerRemoval:
            return removeFillers(text, locale: locale)
        case .whitespaceNormalize:
            return normalizeWhitespace(text)
        case .regexReplace:
            return regexReplace(text, config: stage.config)
        case .templateApply:
            return templateApply(text, config: stage.config)
        case .codeCommentTemplate:
            return codeCommentTemplate(text, config: stage.config)
        case .llmRewrite:
            guard let refineProvider else {
                return text
            }
            let prompt = stage.config["prompt"]
            let request = RefineRequest(sessionID: sessionID, text: text, context: prompt, locale: locale)
            let result = try await refineProvider.refine(request)
            return result.text
        }
    }

    private func smartPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        if trimmed.hasSuffix("。") || trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("？") || trimmed.hasSuffix("?") {
            return trimmed
        }
        return trimmed + "。"
    }

    private func removeFillers(_ text: String, locale: String) -> String {
        let fillerMap: [String: [String]] = [
            "zh-Hans": ["嗯", "啊", "呃", "额", "那个"],
            "en": ["um", "uh", "like", "you know"],
            "ja": ["えー", "あの", "その"]
        ]
        let fillers = fillerMap[locale] ?? fillerMap["en"]!
        var result = text
        for filler in fillers {
            result = result.replacingOccurrences(of: filler, with: "", options: .caseInsensitive)
        }
        return normalizeWhitespace(result)
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func regexReplace(_ text: String, config: [String: String]) -> String {
        guard let pattern = config["pattern"], let replacement = config["replacement"] else {
            return text
        }
        return text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private func templateApply(_ text: String, config: [String: String]) -> String {
        guard let template = config["template"] else {
            return text
        }
        return template.replacingOccurrences(of: "{{text}}", with: text)
    }

    private func codeCommentTemplate(_ text: String, config: [String: String]) -> String {
        let style = config["style", default: "swift"]
        switch style {
        case "js", "ts":
            return "/** \(text) */"
        case "python":
            return "# \(text)"
        default:
            return "/// \(text)"
        }
    }
}
