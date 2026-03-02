import Foundation

/// Analytics are disabled in this build.
/// Keep the existing public API so call sites do not need to change.
final class AnalyticsService {
    static let shared = AnalyticsService()

    private init() {}

    func bootstrap() {
        // no-op
    }

    func setEnabled(_ enabled: Bool) {
        // no-op
        _ = enabled
    }

    func capture(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        // no-op
        _ = event
        _ = properties
    }
}
