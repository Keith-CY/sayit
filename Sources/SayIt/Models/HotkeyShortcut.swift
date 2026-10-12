import AppKit
import Foundation

struct HotkeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifierFlags: NSEvent.ModifierFlags
    enum CodingKeys: String, CodingKey { case keyCode, modifierFlagsRawValue }

    /// Shortcut in the standard macOS notation: modifiers in ⌃⌥⇧⌘ order followed by
    /// the key, with no separators (e.g. "⌥⌘R"). Modifier-only shortcuts read as
    /// "Right ⌥".
    var displayString: String {
        let key = Self.keyCodeToString(keyCode)
            ?? String(Character(UnicodeScalar(self.keyCode) ?? "?"))

        // A modifier-only shortcut already names its key; don't repeat its own flag.
        var flags = self.modifierFlags
        if let ownFlag = Self.modifierFlag(forKeyCode: self.keyCode) {
            flags.remove(ownFlag)
        }

        var symbols = ""
        if flags.contains(.function) { symbols += "fn " }
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }

        guard !symbols.isEmpty else { return key }
        // Word-like keys ("Right ⌥", "Space") read better with a space after the symbols.
        let separator = key.count > 1 && !Self.symbolKeys.contains(key) ? " " : ""
        return symbols + separator + key
    }

    private static let symbolKeys: Set<String> = ["↩", "⇥", "⌫", "⎋", "←", "→", "↓", "↑"]

    private static func modifierFlag(forKeyCode keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command
        case 58, 61: return .option
        case 59, 62: return .control
        case 56, 60: return .shift
        case 63: return .function
        default: return nil
        }
    }

    static func keyCodeToString(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 55: return "Left ⌘"
        case 54: return "Right ⌘"
        case 58: return "Left ⌥"
        case 61: return "Right ⌥"
        case 59: return "Left ⌃"
        case 62: return "Right ⌃"
        case 56: return "Left ⇧"
        case 60: return "Right ⇧"
        case 63: return "fn"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case 24: return "="
        case 27: return "-"
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 39: return "'"
        case 42: return "\\"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 50: return "`"
        default: return nil
        }
    }
}

extension HotkeyShortcut {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        let raw = try c.decode(UInt.self, forKey: .modifierFlagsRawValue)
        self.modifierFlags = NSEvent.ModifierFlags(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(self.keyCode, forKey: .keyCode)
        try c.encode(self.modifierFlags.rawValue, forKey: .modifierFlagsRawValue)
    }
}
