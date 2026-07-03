import AppKit

/// Custom view that draws only a border stroke
final class BorderView: NSView {
    var borderColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    var borderThickness: CGFloat = 8 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard borderColor != .clear else { return }

        borderColor.setStroke()

        let halfThickness = borderThickness / 2
        let rect = bounds.insetBy(dx: halfThickness, dy: halfThickness)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = borderThickness
        path.stroke()
    }
}

/// Manages a transparent overlay window that displays a colored border around a selected screen
@MainActor
final class BorderOverlayController {
    private var overlayWindow: NSWindow?
    private var borderView: BorderView?

    private var currentTally: TallyState = .clear
    private var currentScreenIndex: Int = -1

    // MARK: - Setup

    func setup() {
        createOverlayWindow()

        // Watch for screen changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateWindowFrame()
            }
        }
    }

    /// Returns the screen for the given index, falling back to main screen
    private func screen(for index: Int) -> NSScreen? {
        let screens = NSScreen.screens
        if index >= 0 && index < screens.count {
            return screens[index]
        }
        return NSScreen.main
    }

    private func createOverlayWindow() {
        let settings = AppSettings.shared
        currentScreenIndex = settings.selectedScreenIndex

        guard let screen = screen(for: currentScreenIndex) else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Configure window to be transparent and click-through
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false

        // Create the border view
        let view = BorderView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.borderThickness = CGFloat(settings.borderThickness)
        window.contentView = view

        // Initially hidden
        window.orderOut(nil)

        overlayWindow = window
        borderView = view
    }

    private func updateWindowFrame() {
        let settings = AppSettings.shared

        // If screen changed, recreate the window
        if currentScreenIndex != settings.selectedScreenIndex {
            let wasVisible = overlayWindow?.isVisible ?? false
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
            borderView = nil
            createOverlayWindow()
            if wasVisible {
                overlayWindow?.orderFrontRegardless()
            }
            return
        }

        guard let screen = screen(for: currentScreenIndex), let window = overlayWindow else { return }
        window.setFrame(screen.frame, display: true)
        borderView?.frame = NSRect(origin: .zero, size: screen.frame.size)
    }

    // MARK: - Tally Updates

    func updateTally(_ tally: TallyState) {
        let settings = AppSettings.shared

        // Check if screen changed
        if currentScreenIndex != settings.selectedScreenIndex {
            updateWindowFrame()
        }

        guard tally != currentTally else { return }
        currentTally = tally

        // Determine if we should show the border
        let shouldShow: Bool
        switch tally {
        case .program, .previewProgram:
            shouldShow = true
        case .preview:
            shouldShow = settings.showBorderOnPreview
        case .clear:
            shouldShow = false
        }

        // Update border view
        borderView?.borderThickness = CGFloat(settings.borderThickness)
        borderView?.borderColor = tally.color

        // Show or hide window
        if shouldShow {
            overlayWindow?.orderFrontRegardless()
        } else {
            overlayWindow?.orderOut(nil)
        }
    }

    // MARK: - Cleanup

    func teardown() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        borderView = nil
    }
}
