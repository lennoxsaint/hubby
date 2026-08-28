import AppKit
import CoreGraphics

/// Synthetic keyboard input, used ONLY by the guarded prompt actuator.
/// Covered by the same Accessibility TCC grant as window raising —
/// `CGEventPost` to the HID tap is a no-op without it.
///
/// Contract (AGENTS.md): nothing in Hubby may call these without first
/// re-verifying, against the source-of-truth session data, that the exact
/// prompt being answered is still pending AND the target app is frontmost.
enum Keystrokes {
    private static let returnKey: CGKeyCode = 36
    private static let downArrowKey: CGKeyCode = 125

    static func pressDown() {
        press(downArrowKey)
    }

    static func pressReturn() {
        press(returnKey)
    }

    /// Type literal text (the Nudge's "continue") via the unicode-string
    /// path, so keyboard layout can't garble it.
    static func type(_ text: String) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else { return }
        let chars = Array(text.utf16)
        down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func press(_ key: CGKeyCode) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
