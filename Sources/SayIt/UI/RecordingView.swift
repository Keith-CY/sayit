//
//  RecordingView.swift
//  SayIt
//
//  Recording controls and configuration view
//

import AVFoundation
import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @Environment(\.theme) private var theme
    @Binding var appear: Bool

    let stopAndProcessTranscription: () async -> Void
    let startRecording: () -> Void

    private var recordingControlAction: RecordingControlAction {
        RecordingControlPolicy.action(
            isRunning: self.asr.isRunning,
            isStarting: self.asr.isStarting,
            isReady: self.asr.isAsrReady,
            isPreparingModel: self.asr.isDownloadingModel || self.asr.isLoadingModel,
            micStatus: self.asr.micStatus
        )
    }

    var body: some View {
        ThemedCard(style: .prominent) {
            VStack(alignment: .leading, spacing: Space.md) {
                ActivityUI.Header("Dictation", subtitle: self.statusText)

                Button(action: self.performAction) {
                    HStack(spacing: Space.sm) {
                        if self.recordingControlAction == .starting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: self.recordingControlAction == .stop ? "stop.fill" : "mic")
                                .accessibilityHidden(true)
                        }
                        Text(self.recordingButtonTitle)
                    }
                }
                .buttonStyle(.sayIt(.primary, size: .large, fullWidth: true, isRecording: self.asr.isRunning))
                .disabled(
                    self.recordingControlAction == .waitForModel
                        || self.recordingControlAction == .starting
                )
            }
        }
        .padding(Space.lg)
    }

    private var statusText: String {
        if self.asr.isRunning { return "Recording…" }
        if self.asr.isStarting { return "Starting the microphone…" }
        return self.asr.isAsrReady ? "Ready to dictate." : "The speech model isn’t ready yet."
    }

    private func performAction() {
        switch self.recordingControlAction {
        case .starting, .waitForModel:
            break
        case .stop:
            Task {
                await self.stopAndProcessTranscription()
            }
        case .start, .requestMicrophoneAccess, .showMicrophoneRestriction:
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

    private var recordingButtonTitle: String {
        switch self.recordingControlAction {
        case .start, .prepareAndStart:
            return "Start Dictating"
        case .starting:
            return "Starting Microphone…"
        case .stop:
            return "Stop Dictating"
        case .waitForModel:
            return "Preparing Speech Model…"
        case .requestMicrophoneAccess:
            return "Allow Microphone Access"
        case .openMicrophoneSettings:
            return "Open Microphone Settings"
        case .showMicrophoneRestriction:
            return "Microphone Access Restricted"
        }
    }
}
