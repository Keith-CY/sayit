import Foundation

/// Shared gating logic for whether dictation AI post-processing is usable/configured.
enum DictationAIPostProcessingGate {
    /// Returns true if dictation AI post-processing should be allowed, given current settings.
    /// - Requires `SettingsStore.shared.enableAIProcessing == true`
    /// - For Apple Intelligence: requires `AppleIntelligenceService.isAvailable`
    /// - For other providers: requires a base URL, usable model, and either a
    ///   local endpoint or a non-empty API key
    static func isConfigured() -> Bool {
        let settings = SettingsStore.shared
        guard settings.enableAIProcessing else { return false }

        let providerID = settings.selectedProviderID
        if providerID == "apple-intelligence" {
            return AppleIntelligenceService.isAvailable
        }

        return settings.isAIConfigured
    }

    static func baseURL(for providerID: String, settings: SettingsStore) -> String {
        settings.baseURL(for: providerID).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isLocalEndpoint(_ urlString: String) -> Bool {
        ModelRepository.shared.isLocalEndpoint(urlString)
    }
}
