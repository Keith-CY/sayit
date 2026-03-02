import Foundation

// MARK: - Shared app identity

enum AppIdentity {
    static let displayName = "SayIt"
    static let legacyDisplayName = "SayIt"
    static let menuStatusReady = "Ready to Record"
    static let menuStatusRecording = "Recording..."
    static let menuOpenItem = "Open \(displayName)"
    static let menuQuitItem = "Quit \(displayName)"

    static let defaultDictionaryTerm = "SayIt"
    static let defaultDictionaryAliases = ["say it", "sayit"]
    static let defaultDictionaryAliasesDisplay = "say it, sayit"
    static let parakeetBrandBadge = "\(displayName) Pick"

    static let appSupportFolder = "SayIt"
    static let legacyAppSupportFolder = "SayIt"

    static let keychainService = "com.sayit.provider-api-keys"
    static let legacyKeychainService = "com.sayit.provider-api-keys"
    static let keychainAccount = "apiKeys"

    static let defaultsAccessibilityRestartKey = "SayIt_AccessibilityRestartPending"
    static let defaultsAutoRestartedAccessibilityKey = "SayIt_HasAutoRestartedForAccessibility"
}
