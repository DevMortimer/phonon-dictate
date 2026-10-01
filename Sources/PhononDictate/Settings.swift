import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut. `modifiers` uses Carbon flags (cmdKey, optionKey, ...).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    static let `default` = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), key: "Space")

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up",
        kVK_PageDown: "Page Down",
    ]

    /// A shortcut from a key-down event, or nil when the event has no modifier and is not a function key.
    init?(event: NSEvent) {
        let code = Int(event.keyCode)
        let mods = Shortcut.carbonModifiers(event.modifierFlags)
        let fkey = Shortcut.functionKeys[code]
        guard mods != 0 || fkey != nil else { return nil }
        let name = fkey ?? Shortcut.namedKeys[code] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
        self.init(keyCode: UInt32(code), modifiers: mods, key: name)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }
}

/// User settings, saved in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    /// Retention choices in days. 0 means keep forever.
    static let retentionChoices = [1, 7, 30, 90, 365, 0]

    static func retentionLabel(_ days: Int) -> String {
        switch days {
        case 0: return "Forever"
        case 1: return "1 day"
        default: return "\(days) days"
        }
    }

    private let defaults = UserDefaults.standard

    @Published var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") }
    }
    @Published var recordingRetentionDays: Int {
        didSet { defaults.set(recordingRetentionDays, forKey: "recordingRetentionDays") }
    }
    @Published var historyRetentionDays: Int {
        didSet { defaults.set(historyRetentionDays, forKey: "historyRetentionDays") }
    }
    /// True while the settings window captures a new shortcut. The global hotkeys are off then.
    @Published var capturingShortcut = false

    private init() {
        if let data = defaults.data(forKey: "shortcut"),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = s
        } else {
            shortcut = .default
        }
        recordingRetentionDays = defaults.object(forKey: "recordingRetentionDays") as? Int ?? 7
        historyRetentionDays = defaults.object(forKey: "historyRetentionDays") as? Int ?? 30
    }
}
