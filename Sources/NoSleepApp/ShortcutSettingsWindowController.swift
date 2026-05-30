import AppKit
import KeyboardShortcuts

/// A tiny settings window holding the shortcut recorder, opened from the
/// "Change Shortcut…" menu item.
final class ShortcutSettingsWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if window == nil { window = makeWindow() }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let label = NSTextField(labelWithString: "Toggle NoSleep:")
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggle)

        let row = NSStackView(views: [label, recorder])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline

        let reset = NSButton(title: "Reset to ⌃⌘S", target: self, action: #selector(resetTapped))
        reset.bezelStyle = .rounded

        let hint = NSTextField(labelWithString: "Click the field, then press your key combination.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [row, hint, reset])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        win.title = "NoSleep Shortcut"
        win.contentView = container
        win.isReleasedWhenClosed = false
        return win
    }

    @objc private func resetTapped() {
        KeyboardShortcuts.reset(.toggle)
    }
}
