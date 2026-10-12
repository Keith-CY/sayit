//
//  AppDelegate.swift
//  SayIt
//
//  Created by Barathwaj Anandan on 9/22/25.
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring up file logging + crash handlers immediately during launch.
        _ = FileLogger.shared
        DebugLogger.shared.info("Application launched", source: "AppDelegate")

        // As a unit-test host, stay out of the user's way: no permission prompts,
        // no focus stealing, no visible windows.
        if AppEnvironment.isRunningTests {
            DispatchQueue.main.async {
                NSApp.windows.forEach { $0.orderOut(nil) }
            }
            return
        }

        // Accessibility is requested from Home after SayIt explains why it's needed,
        // never by a system prompt at launch.

        // Initialize app settings (dock visibility, etc.)
        SettingsStore.shared.initializeAppSettings()

        // Bring the app to front on initial launch.
        // Use a few delayed retries because SwiftUI window creation can lag app launch callbacks.
        self.forceFrontOnLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DebugLogger.shared.info("Application will terminate", source: "AppDelegate")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Ensure dock-icon reopen always foregrounds SayIt.
        sender.activate(ignoringOtherApps: true)

        if let mainWindow = AppWindowHelper.primaryWindow(in: sender) {
            mainWindow.orderFrontRegardless()
            mainWindow.makeKeyAndOrderFront(nil)
        }

        return true
    }

    private func forceFrontOnLaunch() {
        for delay in [0.0, 0.12, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.bringMainWindowToFront()
            }
        }
    }

    private func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = AppWindowHelper.primaryWindow() {
            AppWindowHelper.bringToFront(mainWindow)
        }
    }
}

enum AccessibilityPermissionAction {
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    static func perform(
        prompt: () -> Void,
        openSettings: (URL) -> Void
    ) {
        prompt()
        guard let settingsURL else { return }
        openSettings(settingsURL)
    }
}

// MARK: - Session Debounce State

enum AccessibilityPromptPolicy {
    static func shouldPrompt(
        isTrusted: Bool,
        hasPromptedThisSession: Bool,
        now: TimeInterval,
        lastPromptAt: TimeInterval,
        lastPromptBuild: String?,
        currentBuild: String,
        cooldown: TimeInterval
    ) -> Bool {
        guard !isTrusted, !hasPromptedThisSession else { return false }

        let promptedRecently = lastPromptAt > 0 && (now - lastPromptAt) < cooldown
        return !promptedRecently || lastPromptBuild != currentBuild
    }
}
