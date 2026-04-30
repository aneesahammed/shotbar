import AppKit

// MARK: - HUD toast

final class Toast {
    enum Kind {
        case info
        case success
        case error

        var iconName: String? {
            switch self {
            case .info:    return nil
            case .success: return "checkmark.circle.fill"
            case .error:   return "exclamationmark.triangle.fill"
            }
        }

        var iconColor: NSColor {
            switch self {
            case .info:    return .secondaryLabelColor
            case .success: return .systemGreen
            case .error:   return .systemRed
            }
        }

        var defaultDuration: TimeInterval {
            switch self {
            case .info, .success: return 1.4
            case .error:          return 3.5
            }
        }
    }

    private var window: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(text: String, kind: Kind = .info, duration: TimeInterval? = nil) {
        // Dismiss any in-flight toast immediately so the new one is not queued behind it.
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        if let existing = window {
            existing.orderOut(nil)
            window = nil
        }

        let label = NSTextField(labelWithString: text)
        label.textColor = .labelColor
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1

        let iconView: NSImageView? = kind.iconName.flatMap { name in
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return nil }
            let view = NSImageView(image: image)
            view.contentTintColor = kind.iconColor
            view.imageScaling = .scaleProportionallyUpOrDown
            return view
        }

        let hPad: CGFloat = 14
        let vPad: CGFloat = 9
        let iconSize: CGFloat = 18
        let iconGap: CGFloat = iconView != nil ? 8 : 0
        let labelSize = label.intrinsicContentSize
        let frameWidth = hPad * 2 + (iconView != nil ? iconSize + iconGap : 0) + labelSize.width
        let frameHeight = max(iconSize, labelSize.height) + vPad * 2
        let frame = NSRect(x: 0, y: 0, width: frameWidth, height: frameHeight)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let bg = NSVisualEffectView(frame: frame)
        bg.material = .hudWindow
        bg.blendingMode = .withinWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true

        var x = hPad
        if let iconView {
            iconView.frame = NSRect(x: x, y: (frame.height - iconSize) / 2, width: iconSize, height: iconSize)
            bg.addSubview(iconView)
            x += iconSize + iconGap
        }
        label.frame = NSRect(
            x: x,
            y: (frame.height - labelSize.height) / 2 - 1,
            width: labelSize.width,
            height: labelSize.height
        )
        bg.addSubview(label)
        panel.contentView = bg

        // Position on the screen the cursor is currently on, inside visibleFrame
        // so we never collide with the menu bar / notch.
        let cursorScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        if let screen = cursorScreen {
            let visible = screen.visibleFrame
            let origin = CGPoint(
                x: visible.maxX - frame.width - 20,
                y: visible.maxY - frame.height - 12
            )
            panel.setFrameOrigin(origin)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        self.window = panel

        // Announce to VoiceOver.
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )

        let lifetime = duration ?? kind.defaultDuration
        let work = DispatchWorkItem { [weak self] in
            guard let self, let win = self.window, win === panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                win.animator().alphaValue = 0
            }, completionHandler: {
                win.orderOut(nil)
                if self.window === win { self.window = nil }
            })
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime, execute: work)
    }
}
