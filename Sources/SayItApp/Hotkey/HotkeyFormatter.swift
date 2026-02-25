import AppKit
import Carbon
import Foundation
import SayItCore

enum HotkeyFormatter {
    private static let allowedModifiers: UInt32 = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    static func normalizedModifiers(_ modifiers: UInt32) -> UInt32 {
        modifiers & allowedModifiers
    }

    static func hasModifier(_ modifiers: UInt32) -> Bool {
        normalizedModifiers(modifiers) != 0
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            result |= UInt32(cmdKey)
        }
        return normalizedModifiers(result)
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        let modifierText = modifierGlyphs(for: modifiers)
        let keyText = keyName(for: keyCode)
        if modifierText.isEmpty {
            return keyText
        }
        return modifierText + keyText
    }

    static func defaultDisplayString() -> String {
        let config = AppConfig.HotkeyConfig()
        return displayString(keyCode: config.keyCode, modifiers: config.modifiers)
    }

    private static func modifierGlyphs(for modifiers: UInt32) -> String {
        let normalized = normalizedModifiers(modifiers)
        var text = ""
        if normalized & UInt32(controlKey) != 0 {
            text += "⌃"
        }
        if normalized & UInt32(optionKey) != 0 {
            text += "⌥"
        }
        if normalized & UInt32(shiftKey) != 0 {
            text += "⇧"
        }
        if normalized & UInt32(cmdKey) != 0 {
            text += "⌘"
        }
        return text
    }

    private static func keyName(for keyCode: UInt32) -> String {
        if let name = specialKeys[keyCode] {
            return name
        }
        if let name = alphaNumericKeys[keyCode] {
            return name
        }
        return "Key(\(keyCode))"
    }

    private static let specialKeys: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
    ]

    private static let alphaNumericKeys: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3",
        21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
    ]
}
