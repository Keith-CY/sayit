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

        // Request accessibility permissions for global hotkey monitoring
        self.requestAccessibilityPermissions()

        // Initialize app settings (dock visibility, etc.)
        SettingsStore.shared.initializeAppSettings()

        // Bring the app to front on initial launch.
        // Use a few delayed retries because SwiftUI window creation can lag app launch callbacks.
        self.forceFrontOnLaunch()

        // Note: App UI is designed with dark color scheme in mind
        // All gradients and effects are optimized for dark mode
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

    private func requestAccessibilityPermissions() {
        // Never show if already trusted
        guard !AXIsProcessTrusted() else { return }

        // Per-session debounce
        if AXPromptState.hasPromptedThisSession { return }

        // Cooldown: avoid re-prompting too often across launches
        let cooldownKey = "AXLastPromptAt"
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: cooldownKey)
        let oneDay: Double = 24 * 60 * 60
        if last > 0, (now - last) < oneDay {
            return
        }

        DebugLogger.shared.warning("Accessibility permissions required for global hotkeys.", source: "AppDelegate")
        DebugLogger.shared.info("Prompting for Accessibility permission…", source: "AppDelegate")

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        AXPromptState.hasPromptedThisSession = true
        UserDefaults.standard.set(now, forKey: cooldownKey)

        // If still not trusted shortly after, deep-link to the Accessibility pane for convenience
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard !AXIsProcessTrusted(),
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Session Debounce State

private enum AXPromptState {
    static var hasPromptedThisSession: Bool = false
}
