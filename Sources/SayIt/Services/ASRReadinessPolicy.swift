import AVFoundation
import Foundation

enum ASRStartupPolicy {
    static let disablePreloadEnvironmentKey = "SAYIT_TEST_DISABLE_MODEL_PRELOAD"

    static func shouldLoadCachedModel(isReady: Bool, modelsExistOnDisk: Bool) -> Bool {
        !isReady && modelsExistOnDisk
    }

    static func isModelPreloadDisabled(environment: [String: String]) -> Bool {
        environment[self.disablePreloadEnvironmentKey] == "1"
    }
}

enum RecordingControlAction: Equatable {
    case start
    case stop
    case prepareAndStart
    case waitForModel
    case requestMicrophoneAccess
    case openMicrophoneSettings
    case showMicrophoneRestriction
}

enum RecordingControlPolicy {
    static func action(
        isRunning: Bool,
        isReady: Bool,
        isPreparingModel: Bool,
        micStatus: AVAuthorizationStatus = .authorized
    ) -> RecordingControlAction {
        if isRunning {
            return .stop
        }

        switch micStatus {
        case .authorized:
            break
        case .notDetermined:
            return .requestMicrophoneAccess
        case .denied:
            return .openMicrophoneSettings
        case .restricted:
            return .showMicrophoneRestriction
        @unknown default:
            return .openMicrophoneSettings
        }

        if isReady {
            return .start
        }
        if isPreparingModel {
            return .waitForModel
        }
        return .prepareAndStart
    }
}
