import AppKit

/// Fallback in-app toast for when UserNotifications authorization is denied
/// or errors (ad-hoc-signed builds sometimes never get the auth prompt).
/// A floating, non-activating panel in the top-right corner that shows on
/// every space and auto-dismisses.
enum ToastPanel {
    private static var panel: NSPanel?

    static func show(title: String, body: String, seconds: TimeInterval = 90) {
        panel?.close()
        panel = nil

        let width: CGFloat = 360
        let pad: CGFloat = 14

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.preferredMaxLayoutWidth = width - 2 * pad

        let stack = NSStackView(views: [titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        stack.translatesAutoresizingMaskIntoConstraints = true

        let size = NSSize(width: width, height: stack.fittingSize.height)
        stack.frame = NSRect(origin: .zero, size: size)

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = effect

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - size.width - 16,
                                     y: f.maxY - size.height - 16))
        }
        p.orderFrontRegardless()
        panel = p

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak p] in
            p?.close()
            if panel === p { panel = nil }
        }
    }
}
