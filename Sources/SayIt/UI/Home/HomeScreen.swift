//
//  HomeScreen.swift
//  SayIt
//
//  Home: setup until SayIt works end to end, then status, test area and recent
//  dictations. Builds `HomeState` from live services and renders `HomeView`.
//

import AppKit
import AVFoundation
import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var appServices: AppServices
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var history = TranscriptionHistoryStore.shared
    @ObservedObject var downloader: HomeModelDownloader

    @Binding var selectedSidebarItem: SidebarItem?
    @Binding var firstDictationDone: Bool
    var isTranscriptionFocused: FocusState<Bool>.Binding

    let accessibilityEnabled: Bool
    let accessibilityNeedsRestart: Bool
    let stopAndProcessTranscription: () async -> Void
    let startRecording: () -> Void
    let openAccessibilitySettings: () -> Void
    let restartApp: () -> Void

    private var asr: ASRService { self.appServices.asr }

    private static let recentLimit = 3

    var body: some View {
        HomeView(
            state: self.homeState,
            testArea: self.testAreaState,
            transcript: Binding(
                get: { self.asr.finalText },
                set: { self.asr.finalText = $0 }
            ),
            isTranscriptFocused: self.isTranscriptionFocused,
            actions: self.actions
        )
        .onAppear {
            // Refresh permission and model status right away so Home never shows stale state.
            Task { @MainActor in
                self.asr.refreshMicAuthorizationStatus()
                await self.asr.checkIfModelsExistAsync()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.asr.refreshMicAuthorizationStatus()
        }
    }

    // MARK: - State

    private var homeState: HomeState {
        let commandShortcut = self.settings.commandModeShortcutEnabled
            ? self.settings.commandModeHotkeyShortcut.displayString
            : nil
        let editShortcut = self.settings.rewriteModeShortcutEnabled
            ? self.settings.rewriteModeHotkeyShortcut.displayString
            : nil

        return HomeState(
            micStatus: self.asr.micStatus,
            accessibilityEnabled: self.accessibilityEnabled,
            accessibilityNeedsRestart: self.accessibilityNeedsRestart,
            model: SpeechModelSummary(self.settings.selectedSpeechModel),
            modelState: self.modelState,
            firstDictationDone: self.firstDictationDone,
            aiEnhancementConfigured: self.settings.isAIConfigured,
            aiEnhancementEnabled: self.settings.enableAIProcessing,
            shortcut: self.settings.hotkeyShortcut.displayString,
            commandShortcut: commandShortcut,
            editShortcut: editShortcut,
            historyEnabled: self.settings.saveTranscriptionHistory,
            recent: self.history.entries.prefix(Self.recentLimit).map { entry in
                let processed = entry.processedText.trimmingCharacters(in: .whitespacesAndNewlines)
                return RecentDictation(
                    id: entry.id,
                    text: processed.isEmpty ? entry.rawText : processed,
                    appName: entry.appName,
                    date: entry.timestamp
                )
            }
        )
    }

    private var modelState: SpeechModelState {
        let model = self.settings.selectedSpeechModel

        if self.asr.isAsrReady {
            return .ready
        }
        if self.downloader.modelID == model.id {
            switch self.downloader.phase {
            case let .downloading(fraction):
                return .downloading(fraction: fraction, cancellable: true)
            case let .failed(message):
                return .failed(message)
            case .cancelled:
                return self.asr.modelsExistOnDisk ? .onDisk : .cancelled
            case .idle:
                break
            }
        }
        if self.asr.isLoadingModel {
            return .loading
        }
        // Started elsewhere (Voice Engine): show progress, but cancel lives there.
        if self.asr.downloadingModelId == model.id || self.asr.isDownloadingModel {
            return .downloading(fraction: self.asr.downloadProgress, cancellable: false)
        }
        if self.asr.modelsExistOnDisk {
            return .onDisk
        }
        return .missing
    }

    private var testAreaState: HomeTestAreaState {
        HomeTestAreaState(
            action: RecordingControlPolicy.action(
                isRunning: self.asr.isRunning,
                isStarting: self.asr.isStarting,
                isReady: self.asr.isAsrReady,
                isPreparingModel: self.asr.isDownloadingModel || self.asr.isLoadingModel,
                micStatus: self.asr.micStatus
            ),
            isRunning: self.asr.isRunning,
            transcript: self.asr.finalText,
            isDictatingElsewhere: self.asr.isRunning && !(NSApp.isActive && self.isTranscriptionFocused.wrappedValue),
            wordBoostText: self.settings.selectedSpeechModel == .parakeetTDT ? self.asr.wordBoostStatusText : nil
        )
    }

    // MARK: - Actions

    private var actions: HomeActions {
        HomeActions(
            requestMicrophone: { self.asr.requestMicAccess() },
            openMicrophoneSettings: { self.asr.openSystemSettingsForMic() },
            openAccessibilitySettings: self.openAccessibilitySettings,
            restartApp: self.restartApp,
            downloadModel: {
                let model = self.settings.selectedSpeechModel
                if SpeechModelSummary(model).isBuiltIn {
                    Task { await self.prepareModel() }
                } else {
                    self.downloader.start(model, asr: self.asr)
                }
            },
            cancelDownload: { self.downloader.cancel() },
            openVoiceEngine: { self.selectedSidebarItem = .voiceEngine },
            openAIEnhancement: { self.selectedSidebarItem = .aiEnhancement },
            openGeneral: { self.selectedSidebarItem = .general },
            openHistory: { self.selectedSidebarItem = .history },
            openCommandMode: { self.selectedSidebarItem = .commandMode },
            recordingControl: self.performRecordingControl,
            copyTranscript: {
                ClipboardService.copyToClipboard(self.asr.finalText)
            },
            clearTranscript: {
                self.asr.finalText = ""
            }
        )
    }

    private func prepareModel() async {
        do {
            try await self.asr.ensureAsrReady()
        } catch {
            self.asr.errorTitle = "Speech Model Couldn’t Load"
            self.asr.errorMessage = error.localizedDescription
            self.asr.showError = true
        }
    }

    private func performRecordingControl() {
        switch self.testAreaState.action {
        case .starting, .waitForModel, .showMicrophoneRestriction:
            break
        case .stop:
            Task { await self.stopAndProcessTranscription() }
        case .start, .requestMicrophoneAccess:
            self.startRecording()
        case .prepareAndStart:
            Task {
                do {
                    try await self.asr.ensureAsrReady()
                    self.startRecording()
                } catch {
                    self.asr.errorTitle = "Speech Model Couldn’t Load"
                    self.asr.errorMessage = error.localizedDescription
                    self.asr.showError = true
                }
            }
        case .openMicrophoneSettings:
            self.asr.openSystemSettingsForMic()
        }
    }
}
