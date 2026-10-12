//
//  AISettingsView.swift
//  SayIt
//
//  Shared types for the Voice Engine and AI Enhancement settings pages.
//  Created: 2025-12-14
//

import SwiftUI

// MARK: - Connection Status Enum

enum AIConnectionStatus {
    case unknown, testing, success, failed
}

enum PromptEditorMode: Identifiable, Equatable {
    case defaultPrompt(mode: SettingsStore.PromptMode)
    case newPrompt(prefillMode: SettingsStore.PromptMode)
    case edit(promptID: String)

    var id: String {
        switch self {
        case let .defaultPrompt(mode): return "default:\(mode.rawValue)"
        case let .newPrompt(prefillMode): return "new:\(prefillMode.rawValue)"
        case let .edit(promptID): return "edit:\(promptID)"
        }
    }

    var isDefault: Bool {
        if case .defaultPrompt = self { return true }
        return false
    }

    var editingPromptID: String? {
        if case let .edit(promptID) = self { return promptID }
        return nil
    }

    var mode: SettingsStore.PromptMode? {
        switch self {
        case let .defaultPrompt(mode): return mode
        case let .newPrompt(prefillMode): return prefillMode
        case .edit: return nil
        }
    }
}

enum ModelSortOption: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case accuracy = "Accuracy"
    case speed = "Speed"

    var id: String { self.rawValue }
}

enum SpeechProviderFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case nvidia = "NVIDIA"
    case apple = "Apple"
    case openai = "OpenAI"
    case qwen = "Qwen"

    var id: String { self.rawValue }
}

enum AISettingsLayout {
    static let labelWidth: CGFloat = 110
    static let pickerWidth: CGFloat = 220
    static let controlHeight: CGFloat = 34
    static let actionMinWidth: CGFloat = 120
    static let compactActionMinWidth: CGFloat = 96
    static let wideActionMinWidth: CGFloat = 140
    static let primaryActionMinWidth: CGFloat = 150
    static let promptActionMinWidth: CGFloat = 90
    static let rowLeadingIndent: CGFloat = labelWidth + 12
}
