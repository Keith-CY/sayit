import AppKit
import SayItCore
import SwiftUI

struct PipelineEditorView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var language: AppLanguageCenter
    @State private var newStageType: PipelineStageType = .smartPunctuation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker(language.text("settings.pipelineList"), selection: $viewModel.editingPipelineID) {
                    ForEach(viewModel.availablePipelines) { pipeline in
                        Text(pipeline.name).tag(Optional(pipeline.id))
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Button(language.text("settings.pipelineNew")) {
                    viewModel.createPipeline()
                }

                Button(language.text("settings.pipelineDuplicate")) {
                    viewModel.duplicateEditingPipeline()
                }
                .disabled(viewModel.editingPipeline == nil)

                Button(language.text("settings.pipelineDelete")) {
                    viewModel.deleteEditingPipeline()
                }
                .disabled(viewModel.editingPipeline == nil)
            }

            if let pipeline = viewModel.editingPipeline {
                TextField(
                    language.text("settings.pipelineName"),
                    text: Binding(
                        get: { pipeline.name },
                        set: { viewModel.renameEditingPipeline($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)

                Toggle(
                    language.text("settings.pipelineEnabled"),
                    isOn: Binding(
                        get: { pipeline.enabled },
                        set: { viewModel.setEditingPipelineEnabled($0) }
                    )
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(language.text("settings.pipelineStages"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(pipeline.stages) { stage in
                        StageEditorRow(
                            stage: stage,
                            viewModel: viewModel,
                            stageLabel: stageTypeLabel(stage.type),
                            stageEnabledLabel: language.text("settings.stageEnabled"),
                            stageTypeLabel: language.text("settings.stageType"),
                            moveUpLabel: language.text("settings.stageMoveUp"),
                            moveDownLabel: language.text("settings.stageMoveDown"),
                            removeLabel: language.text("settings.stageRemove"),
                            patternLabel: language.text("settings.stageConfigPattern"),
                            replacementLabel: language.text("settings.stageConfigReplacement"),
                            templateLabel: language.text("settings.stageConfigTemplate"),
                            styleLabel: language.text("settings.stageConfigStyle"),
                            promptLabel: language.text("settings.stageConfigPrompt"),
                            stageTypeFormatter: stageTypeLabel(_:)
                        )
                    }

                    HStack(spacing: 8) {
                        Picker(language.text("settings.stageType"), selection: $newStageType) {
                            ForEach(PipelineStageType.allCases, id: \.self) { type in
                                Text(stageTypeLabel(type)).tag(type)
                            }
                        }
                        .pickerStyle(.menu)

                        Button(language.text("settings.stageAdd")) {
                            viewModel.addStage(type: newStageType)
                        }
                    }
                }
            } else {
                Text(language.text("settings.noPipeline"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stageTypeLabel(_ type: PipelineStageType) -> String {
        switch type {
        case .smartPunctuation:
            return language.text("stage.smartPunctuation")
        case .fillerRemoval:
            return language.text("stage.fillerRemoval")
        case .whitespaceNormalize:
            return language.text("stage.whitespaceNormalize")
        case .regexReplace:
            return language.text("stage.regexReplace")
        case .templateApply:
            return language.text("stage.templateApply")
        case .codeCommentTemplate:
            return language.text("stage.codeCommentTemplate")
        case .llmRewrite:
            return language.text("stage.llmRewrite")
        }
    }
}

private struct StageEditorRow: View {
    let stage: PipelineStage
    @ObservedObject var viewModel: SettingsViewModel
    let stageLabel: String
    let stageEnabledLabel: String
    let stageTypeLabel: String
    let moveUpLabel: String
    let moveDownLabel: String
    let removeLabel: String
    let patternLabel: String
    let replacementLabel: String
    let templateLabel: String
    let styleLabel: String
    let promptLabel: String
    let stageTypeFormatter: (PipelineStageType) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle(
                    stageEnabledLabel,
                    isOn: Binding(
                        get: { stage.enabled },
                        set: { viewModel.updateStageEnabled(stageID: stage.id, enabled: $0) }
                    )
                )
                .toggleStyle(.checkbox)

                Picker(
                    stageTypeLabel,
                    selection: Binding(
                        get: { stage.type },
                        set: { viewModel.updateStageType(stageID: stage.id, type: $0) }
                    )
                ) {
                    ForEach(PipelineStageType.allCases, id: \.self) { type in
                        Text(stageTypeFormatter(type)).tag(type)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Button(moveUpLabel) {
                    viewModel.moveStageUp(stageID: stage.id)
                }
                .disabled(!viewModel.canMoveStageUp(stageID: stage.id))

                Button(moveDownLabel) {
                    viewModel.moveStageDown(stageID: stage.id)
                }
                .disabled(!viewModel.canMoveStageDown(stageID: stage.id))

                Button(removeLabel) {
                    viewModel.removeStage(stageID: stage.id)
                }
            }

            stageConfigFields()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .overlay(alignment: .topLeading) {
            Text(stageLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.windowBackgroundColor))
                .offset(x: 8, y: -8)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func stageConfigFields() -> some View {
        switch stage.type {
        case .regexReplace:
            TextField(
                patternLabel,
                text: Binding(
                    get: { viewModel.stageConfigValue(stageID: stage.id, key: "pattern") },
                    set: { viewModel.updateStageConfig(stageID: stage.id, key: "pattern", value: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)

            TextField(
                replacementLabel,
                text: Binding(
                    get: { viewModel.stageConfigValue(stageID: stage.id, key: "replacement") },
                    set: { viewModel.updateStageConfig(stageID: stage.id, key: "replacement", value: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
        case .templateApply:
            TextField(
                templateLabel,
                text: Binding(
                    get: { viewModel.stageConfigValue(stageID: stage.id, key: "template") },
                    set: { viewModel.updateStageConfig(stageID: stage.id, key: "template", value: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
        case .codeCommentTemplate:
            TextField(
                styleLabel,
                text: Binding(
                    get: { viewModel.stageConfigValue(stageID: stage.id, key: "style") },
                    set: { viewModel.updateStageConfig(stageID: stage.id, key: "style", value: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
        case .llmRewrite:
            TextField(
                promptLabel,
                text: Binding(
                    get: { viewModel.stageConfigValue(stageID: stage.id, key: "prompt") },
                    set: { viewModel.updateStageConfig(stageID: stage.id, key: "prompt", value: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
        default:
            EmptyView()
        }
    }
}
