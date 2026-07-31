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
}

enum RecordingControlPolicy {
    static func action(
        isRunning: Bool,
        isReady: Bool,
        isPreparingModel: Bool
    ) -> RecordingControlAction {
        if isRunning {
            return .stop
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
