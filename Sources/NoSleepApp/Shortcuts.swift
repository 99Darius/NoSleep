import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global toggle for keep-awake. Default ⌃⌘S (matches the "S" menu bar icon);
    /// users can rebind it via "Change Shortcut…". KeyboardShortcuts persists any
    /// override in UserDefaults automatically.
    static let toggle = Self("toggleNoSleep", default: .init(.s, modifiers: [.command, .control]))
}
